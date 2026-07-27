# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelDemoManagement::SeedRealtimeScenario do
  include ActiveJob::TestHelper

  let(:logger) { HotelDemoManagement::ResetState::NoopLogger.new }
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, default_currency: "MYR") }
  let!(:user) { create(:user, account: account) }
  let!(:room_type) do
    create(:room_type, hotel: hotel, name: "Deluxe", quantity: 9, base_price: 200, room_numbers: %w[101 102 103 104 105 106 107 108 109])
  end
  let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "Standard Rate", currency: "MYR") }

  let(:reset_success) do
    HotelDemoManagement::ResetState::Result.new(success?: true, hotel: hotel)
  end

  def build_service(**overrides)
    described_class.new(
      hotel: hotel,
      logger: logger,
      booking_count: 25,
      group_count: 5,
      history_days: 5,
      future_days: 3,
      **overrides
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    allow(HotelDemoManagement::ResetState).to receive(:new).and_return(instance_double(HotelDemoManagement::ResetState, call: reset_success))
    allow(Bookings::TransitionStatus).to receive(:new) do |booking:, status:, **|
      instance_double(Bookings::TransitionStatus).tap do |service|
        allow(service).to receive(:call) do
          booking.update_column(:status, status)
          OpenStruct.new(success?: true)
        end
      end
    end
    allow(NightAudits::Run).to receive(:new).and_return(instance_double(NightAudits::Run, call: OpenStruct.new(success?: true)))
  end

  after { clear_enqueued_jobs }

  describe "#call" do
    it "plans the default annual booking and group volume" do
      scenarios = described_class.new(hotel: hotel, logger: logger).send(:booking_scenarios)
      group_keys = scenarios.filter_map { |scenario| scenario[:group_key] }.uniq

      expect(scenarios.size).to eq(1_000)
      expect(group_keys.size).to eq(100)
      expect(scenarios.filter_map { |scenario| scenario[:company_key] }.uniq).to match_array(%w[meridian northstar strata])
      expect(scenarios.pluck(:check_in).min).to be >= 365.days.ago.to_date
      expect(scenarios.pluck(:check_in).max).to be <= 30.days.from_now.to_date
    end

    it "calls reset state before seeding realtime bookings" do
      service = instance_double(HotelDemoManagement::ResetState, call: reset_success)
      allow(HotelDemoManagement::ResetState).to receive(:new).and_return(service)

      result = build_service.call

      expect(result).to be_success
      expect(HotelDemoManagement::ResetState).to have_received(:new).with(hotel: hotel, logger: logger, embed: false)
      expect(service).to have_received(:call)
      expect(hotel.bookings.count).to eq(25)
    end

    it "creates complete guests, bookings, rooms, pre-check-ins, and captured payments" do
      result = build_service.call

      expect(result).to be_success
      guest = Guest.find_by!(name: "Ahmad Bin Ibrahim", created_by_hotel: hotel)
      expect(guest).to have_attributes(gender: "male", document_type: "ic", date_of_birth: Date.new(1992, 3, 10))
      expect(guest.booking_guests.first).to have_attributes(
        government_id_snapshot: "920310-14-5183",
        date_of_birth_snapshot: Date.new(1992, 3, 10)
      )
      expect(hotel.bookings.count).to eq(25)
      expect(hotel.bookings.where(
        pre_checkin_status: "completed",
        guarantee_method: "pre_checkin_completed",
        deposit_status: "not_required"
      ).count).to eq(25)
      expect(hotel.bookings.where(payment_status: "captured").count).to eq(18)
      expect(hotel.bookings.where(payment_status: "pending", source: "corporate").count).to eq(7)
      expect(hotel.bookings.where(source: described_class::BOOKING_SOURCES).count).to eq(18)
      expect(hotel.bookings.where("hotel_snapshot ->> 'room_number' IS NULL")).to be_empty
      expect(BookingRoom.joins(:booking).where(bookings: { hotel_id: hotel.id }).count).to eq(25)
      expect(PreCheckin.joins(:booking).where(bookings: { hotel_id: hotel.id }, status: "completed").count).to eq(25)
      expect(PreCheckin.joins(:booking).where(bookings: { hotel_id: hotel.id }).where("pre_checkins.completed_at > ?", Time.current)).to be_empty
      expect(PaymentTransaction.joins(:booking).where(bookings: { hotel_id: hotel.id }, gateway: "manual", status: "captured").count).to eq(18)
      expect(PaymentTransaction.joins(:booking).where(bookings: { hotel_id: hotel.id }).where("captured_at > ?", Time.current)).to be_empty
    end

    it "creates company-only direct billing for selected single and group bookings" do
      result = build_service.call

      expect(result).to be_success
      expect(hotel.hotel_corporate_accounts.count).to eq(3)
      expect(hotel.hotel_corporate_accounts.distinct.pluck(:account_type)).to eq([ "company" ])
      expect(hotel.hotel_corporate_accounts.where(direct_bill_enabled: true).count).to eq(3)

      company_bookings = hotel.bookings.where(source: "corporate").includes(:payment_transactions, :booking_folios)
      expect(company_bookings.count).to eq(7)
      company_bookings.each do |booking|
        expect(booking.payment_transactions).to be_empty
        expect(booking.booking_folio).to have_attributes(folio_type: "guest", payer_type: "guest")
        expect(booking.booking_folios.where(payer_type: "company", folio_type: "external").count).to eq(1)
      end

      corporate_groups = hotel.group_bookings.includes(:bookings).select { |group| group.bookings.any? { |booking| booking.source == "corporate" } }
      expect(corporate_groups).not_to be_empty
      expect(corporate_groups).to all(satisfy { |group| group.bookings.all? { |booking| booking.source == "corporate" } })
    end

    it "reuses deterministic company relationships and guest identities" do
      service = build_service

      first_relationships = service.send(:ensure_company_relationships)
      second_relationships = service.send(:ensure_company_relationships)

      expect(second_relationships.transform_values(&:id)).to eq(first_relationships.transform_values(&:id))
      expect(hotel.hotel_corporate_accounts.count).to eq(3)
      expect(first_relationships.values.map(&:account_type).uniq).to eq([ "company" ])
      expect(service.send(:profile_for, 0)[:email]).to eq(service.send(:profile_for, 25)[:email])
    end

    it "completes company direct billing, AR invoicing, and settlement through real lifecycles" do
      %w[wifi swimming_pool fitness_center spa_wellness_centre laundry].each do |slug|
        Amenity.find_or_create_by!(slug: slug) do |amenity|
          amenity.name = slug.titleize
          amenity.amenity_type = "hotel"
          amenity.category = "General"
          amenity.icon = "star"
        end
      end
      allow(HotelDemoManagement::ResetState).to receive(:new).and_call_original
      allow(Bookings::TransitionStatus).to receive(:new).and_call_original
      allow(NightAudits::Run).to receive(:new).and_call_original

      result = build_service(booking_count: 15, group_count: 2, history_days: 10, future_days: 2).call

      expect(result).to be_success
      expect(hotel.ar_invoices.count).to be_positive
      expect(hotel.ar_invoices.where.not(status: "paid")).to be_empty
      expect(hotel.ar_payments.count).to be_positive
      expect(hotel.ar_payments.all? { |payment| payment.unallocated_amount.zero? }).to be(true)
      company_bookings = hotel.bookings.where(source: "corporate", status: "completed").includes(:booking_folios)
      expect(company_bookings).not_to be_empty
      company_bookings.each do |booking|
        company_folio = booking.booking_folios.find(&:payer_type_company?)
        expect(company_folio.folio_transactions.charge.sum(:amount)).to be_positive
        expect(company_folio.ar_invoice).to be_paid
        expect(booking.booking_folio.outstanding_balance).to be_zero
      end


      historical_cleaning_requests = CheckOutRequest.joins(:booking)
                                                    .where(bookings: { hotel_id: hotel.id })
                                                    .where("bookings.checked_out_at < ?", Time.current.beginning_of_day)
      expect(historical_cleaning_requests).not_to be_empty
      expect(historical_cleaning_requests.distinct.pluck(:status)).to eq([ "completed" ])
      expect(RoomOperationalAuditLog.where(hotel: hotel, event_type: "checkout_room_cleaning_started").count).to eq(historical_cleaning_requests.count)
      expect(RoomOperationalAuditLog.where(hotel: hotel, event_type: "checkout_room_cleaning_completed").count).to eq(historical_cleaning_requests.count)
    end

    it "creates successful multi-room group bookings" do
      result = build_service.call

      expect(result).to be_success
      expect(hotel.group_bookings.count).to eq(5)
      hotel.group_bookings.includes(:bookings).find_each do |group_booking|
        expect(group_booking.bookings.size).to be_between(2, 4)
        expect(group_booking.bookings.map(&:group_position)).to eq((1..group_booking.bookings.size).to_a)
        expect(group_booking.status).to eq(group_booking.projected_status)
      end
    end

    it "does not enqueue guest notifications for generated bookings" do
      expect { build_service.call }
        .to have_enqueued_job(SendReceiptEmailJob).exactly(0).times
        .and have_enqueued_job(SendWhatsappReceiptJob).exactly(0).times
    end

    it "runs successful booking lifecycles and night audits" do
      result = build_service.call

      expect(result).to be_success
      expect(Bookings::TransitionStatus).to have_received(:new).at_least(:once)
      expect(NightAudits::Run).to have_received(:new).exactly(5).times
      expect(hotel.bookings.distinct.pluck(:status)).to match_array(%w[completed confirmed checked_in])
    end

    it "completes every historical cleaning request for a booking without broadcasting demo webhooks" do
      booking = create(:booking, hotel: hotel, status: "completed")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
      requests = [
        create(:check_out_request, booking: booking, status: "new", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" }),
        create(:check_out_request, booking: booking, status: "new", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })
      ]

      expect { build_service.send(:complete_historical_checkout_cleaning, booking) }
        .not_to have_enqueued_job(WebhookBroadcastJob)

      expect(requests.map { |request| request.reload.status }).to all(eq("completed"))
      expect(RoomStatus.find_by!(hotel: hotel, room_number: "101").status).to eq("ready")
      expect(RoomOperationalAuditLog.where(hotel: hotel, event_type: "checkout_room_cleaning_started").count).to eq(1)
      expect(RoomOperationalAuditLog.where(hotel: hotel, event_type: "checkout_room_cleaning_completed").count).to eq(1)
    end

    it "skips conflicting stays instead of double-booking a low-capacity hotel" do
      room_type.update!(quantity: 1, room_numbers: [ "101" ])

      result = build_service.call

      expect(result).to be_success
      stays = hotel.bookings.order(:check_in).pluck(:check_in, :check_out)
      expect(stays.size).to be_between(1, 24)
      expect(stays.each_cons(2).all? { |current, following| current.last <= following.first }).to be(true)
    end

    it "does not assign stale room numbers beyond the room type quantity" do
      room_type.update!(quantity: 1, room_numbers: %w[101 102])

      result = build_service.call

      expect(result).to be_success
      expect(BookingRoom.joins(:booking).where(bookings: { hotel_id: hotel.id }).distinct.pluck(:room_number)).to eq([ "101" ])
    end

    it "returns failure when reset state fails" do
      reset_failure = HotelDemoManagement::ResetState::Result.new(success?: false, hotel: hotel, error: "reset failed")
      allow(HotelDemoManagement::ResetState).to receive(:new).and_return(instance_double(HotelDemoManagement::ResetState, call: reset_failure))

      result = build_service.call

      expect(result).not_to be_success
      expect(result.error).to eq("reset failed")
      expect(hotel.bookings).to be_empty
    end

    it "returns failure when a lifecycle service fails" do
      original_city = hotel.city
      reset_service = instance_double(HotelDemoManagement::ResetState)
      allow(reset_service).to receive(:call) do
        hotel.update!(city: "Reset City")
        reset_success
      end
      allow(HotelDemoManagement::ResetState).to receive(:new).and_return(reset_service)
      failed_transition = instance_double(Bookings::TransitionStatus, call: OpenStruct.new(success?: false, error: "posting blocked"))
      allow(Bookings::TransitionStatus).to receive(:new).and_return(failed_transition)

      result = build_service.call

      expect(result).not_to be_success
      expect(result.error).to include("posting blocked")
      expect(hotel.bookings).to be_empty
      expect(hotel.group_bookings).to be_empty
      expect(hotel.reload.city).to eq(original_city)
    end

    it "returns failure when room setup is invalid after reset" do
      room_type.rate_plans.destroy_all

      result = build_service.call

      expect(result).not_to be_success
      expect(result.error).to include("at least one rate plan")
    end
  end
end
