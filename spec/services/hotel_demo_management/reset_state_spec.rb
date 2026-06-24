# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelDemoManagement::ResetState do
  include ActiveJob::TestHelper

  let(:logger) { described_class::NoopLogger.new }
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, default_currency: "MYR", preferred_channel_manager: nil) }
  let!(:room_type) do
    create(:room_type, hotel: hotel, name: "Deluxe", quantity: 2, base_price: 200, room_numbers: %w[101 102])
  end

  before do
    %w[wifi swimming_pool fitness_center spa_wellness_centre laundry].each do |slug|
      Amenity.find_or_create_by!(slug: slug) do |amenity|
        amenity.name = slug.titleize
        amenity.amenity_type = "hotel"
        amenity.category = "General"
        amenity.icon = "star"
      end
    end

    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  after do
    clear_enqueued_jobs
  end

  describe "#call" do
    it "resets hotel configuration and demo content" do
      hotel.hotel_taxes.create!(name: "Old Tax", rate_type: "flat", amount: 5)
      create(:room_rate, room_type: room_type, date: Date.current, price: 999, currency: "MYR")
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 0, status: "closed")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "999", status: "dirty")
      create(:nearby_attraction, hotel: hotel, name: "Old Attraction")
      create(:hotel_knowledge_document, hotel: hotel, title: "Old Knowledge")

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).to be_success
      expect(hotel.reload).to have_attributes(
        time_zone: "Kuala Lumpur",
        arrival_grace_period: 7200,
        tourism_tax_enabled: true,
        tourism_tax_amount: 10.0,
        sst_enabled: true
      )
      expect(hotel.hotel_taxes.pluck(:name)).to match_array([ "Service Tax", "Service Charge" ])
      expect(room_type.reload.rate_plans.pluck(:name)).to include("Standard Rate", "Non-Refundable Rate")
      expect(room_type.room_rates.where(date: Date.current).pluck(:price)).to match_array([ 200, 180 ])
      expect(room_type.room_inventories.find_by(date: Date.current).available_room_numbers).to eq(%w[101 102])
      expect(room_type.room_statuses.pluck(:room_number, :status)).to match_array([ [ "101", "ready" ], [ "102", "ready" ] ])
      expect(hotel.nearby_attractions.pluck(:name)).to match_array([ "City Centre", "Local Market", "City Park" ])
      expect(hotel.knowledge_documents.count).to eq(6)
      expect(HotelKnowledgeChunk.joins(:document).where(hotel_knowledge_documents: { hotel_id: hotel.id })).to exist
    end

    it "deletes operational records for the hotel" do
      user = create(:user, account: account)
      booking = create(:booking, hotel: hotel)
      folio = create(:booking_folio, hotel: hotel, booking: booking)
      transaction = create(:folio_transaction, booking_folio: folio, user: user)
      create(:folio_operation_log, hotel: hotel, booking: booking, source_folio: folio, source_transaction: transaction)
      create(:folio_routing_rule, hotel: hotel, booking: booking, target_folio: folio)
      create(:payment_transaction, booking: booking, booking_quote: nil)
      create(:night_audit, hotel: hotel, performed_by_user: user)
      create(:hotel_business_date, hotel: hotel, business_date: hotel.current_business_date - 1.day, status: "closed")
      create(:financial_audit_event, hotel: hotel)
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user)
      create(:inventory_audit_log, hotel: hotel, room_type: room_type, user: user)
      create(:room_operational_audit_log, hotel: hotel, room_type: room_type, user: user)
      create(:notification_delivery, hotel: hotel, booking: booking)
      prospect = create(:prospect, hotel: hotel)
      create(:prospect_conversation_state, prospect: prospect)
      create(:prospect_message, prospect: prospect)
      create(:journal_batch, hotel: hotel)

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).to be_success
      expect(hotel.bookings).to be_empty
      expect(BookingFolio.where(id: folio.id)).to be_empty
      expect(FolioTransaction.where(booking_folio_id: folio.id)).to be_empty
      expect(FolioOperationLog.where(booking_id: booking.id)).to be_empty
      expect(FolioRoutingRule.where(booking_id: booking.id)).to be_empty
      expect(PaymentTransaction.where(booking_id: booking.id)).to be_empty
      expect(hotel.night_audits).to be_empty
      expect(hotel.hotel_business_dates.current.count).to eq(1)
      expect(hotel.hotel_business_dates.count).to eq(1)
      expect(FinancialAuditEvent.where(hotel_id: hotel.id)).to be_empty
      expect(BookingAuditLog.where(hotel_id: hotel.id)).to be_empty
      expect(InventoryAuditLog.where(hotel_id: hotel.id)).to be_empty
      expect(RoomOperationalAuditLog.where(hotel_id: hotel.id)).to be_empty
      expect(NotificationDelivery.where(hotel_id: hotel.id)).to be_empty
      expect(hotel.prospects).to be_empty
      expect(hotel.journal_batches).to be_empty
    end

    it "enqueues embeddings only when requested and AI concierge is enabled" do
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "test-key")

      expect {
        described_class.new(hotel: hotel, logger: logger, embed: true).call
      }.to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob).exactly(6).times
    end

    it "does not enqueue embeddings when embed is false" do
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "test-key")

      expect {
        described_class.new(hotel: hotel, logger: logger, embed: false).call
      }.not_to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob)
    end

    it "enqueues channel manager sync when configured" do
      hotel.update!(preferred_channel_manager: "channex")

      expect {
        described_class.new(hotel: hotel, logger: logger).call
      }.to have_enqueued_job(ChannelManagers::SyncJob)
    end

    it "returns failure instead of raising when room setup is invalid" do
      room_type.destroy!

      result = described_class.new(hotel: hotel, logger: logger).call

      expect(result).not_to be_success
      expect(result.error).to include("at least one room type")
    end
  end
end
