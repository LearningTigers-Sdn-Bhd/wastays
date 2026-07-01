# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ExtraChargeReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 6, 1) }
  let(:end_date) { Date.new(2026, 6, 30) }

  describe "#call" do
    it "returns only fb charge rows for the fb tab" do
      booking = create(:booking, hotel: hotel, guest_name: "FB Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "Restaurant", amount: 25, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "other", description: "Laundry", amount: 15, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, tab: "fb").call

      expect(result.active_tab).to eq("fb")
      expect(result.rows.size).to eq(1)
      expect(result.rows.first[:guest_name]).to eq("FB Guest")
      expect(result.rows.first[:category]).to eq("fb")
      expect(result.totals[:transaction_count]).to eq(1)
      expect(result.totals[:total_amount]).to eq(25.to_d)
    end

    it "returns non-fb extra charge rows only for the non_fb tab" do
      booking = create(:booking, hotel: hotel, guest_name: "Extra Guest")
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", description: "Restaurant", amount: 25, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "accommodation", description: "Room", amount: 120, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "Tax", amount: 10, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "parking", description: "Parking", amount: 8, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "other", description: "Laundry", amount: 15, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, tab: "non_fb").call

      expect(result.active_tab).to eq("non_fb")
      expect(result.rows.map { |row| row[:category] }).to eq(%w[parking other])
      expect(result.totals[:transaction_count]).to eq(2)
      expect(result.totals[:total_amount]).to eq(23.to_d)
    end

    it "scopes rows to the selected hotel" do
      booking = create(:booking, hotel: other_hotel, guest_name: "Other Hotel Guest")
      folio = create(:booking_folio, booking: booking, hotel: other_hotel)
      create(:folio_transaction, booking_folio: folio, category: "fb", amount: 30, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, tab: "fb").call

      expect(result.rows).to be_empty
      expect(result.totals[:total_amount]).to eq(0.to_d)
    end

    it "excludes voided transactions" do
      booking = create(:booking, hotel: hotel)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      voiding_txn = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction", amount: 20, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "fb", amount: 20, posting_date: start_date, voided_by_transaction_id: voiding_txn.id)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, tab: "fb").call

      expect(result.rows).to be_empty
    end
  end
end
