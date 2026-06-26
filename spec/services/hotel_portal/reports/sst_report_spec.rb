# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::SstReport, type: :service do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:other_hotel) { create(:hotel, sst_enabled: true) }
  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }

  describe "#call" do
    it "includes bookings with SST transactions in the date range" do
      booking = create(:booking, hotel: hotel, guest_name: "SST Guest", check_in: start_date, check_out: start_date + 2.days)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 200.00, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 200.00, posting_date: start_date + 1.day)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "Service Tax (SST 8%)", amount: 16.00, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "Service Tax (SST 8%)", amount: 16.00, posting_date: start_date + 1.day)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(1)
      expect(result.rows.first[:guest_name]).to eq("SST Guest")
      expect(result.rows.first[:sst_amount]).to eq(32.0.to_d)
      expect(result.rows.first[:taxable_amount]).to eq(400.0.to_d)
      expect(result.rows.first[:total_amount]).to eq(432.0.to_d)
    end

    it "excludes bookings from other hotels" do
      other_booking = create(:booking, hotel: other_hotel, check_in: start_date, check_out: start_date + 1.day)
      other_folio = create(:booking_folio, booking: other_booking, hotel: other_hotel)
      create(:folio_transaction, booking_folio: other_folio, category: "tax", description: "Service Tax (SST 8%)", amount: 16.00, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows).to be_empty
    end

    it "excludes voided SST transactions" do
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      voiding_txn = create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "correction", amount: 16.00, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "Service Tax (SST 8%)", amount: 16.00, posting_date: start_date, voided_by_transaction_id: voiding_txn.id)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows).to be_empty
    end

    it "excludes SST transactions outside the date range" do
      booking = create(:booking, hotel: hotel, check_in: start_date - 10.days, check_out: start_date - 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "Service Tax (SST 8%)", amount: 16.00, posting_date: start_date - 5.days)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows).to be_empty
    end

    it "aggregates totals across multiple bookings" do
      booking1 = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 1.day)
      folio1 = create(:booking_folio, booking: booking1, hotel: hotel)
      create(:folio_transaction, booking_folio: folio1, category: "accommodation", amount: 100.00, posting_date: start_date)
      create(:folio_transaction, booking_folio: folio1, category: "tax", description: "Service Tax (SST 8%)", amount: 8.00, posting_date: start_date)

      booking2 = create(:booking, hotel: hotel, check_in: start_date + 5.days, check_out: start_date + 6.days)
      folio2 = create(:booking_folio, booking: booking2, hotel: hotel)
      create(:folio_transaction, booking_folio: folio2, category: "accommodation", amount: 200.00, posting_date: start_date + 5.days)
      create(:folio_transaction, booking_folio: folio2, category: "tax", description: "Service Tax (SST 8%)", amount: 16.00, posting_date: start_date + 5.days)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(2)
      expect(result.totals[:booking_count]).to eq(2)
      expect(result.totals[:sst_amount]).to eq(24.0.to_d)
      expect(result.totals[:taxable_amount]).to eq(300.0.to_d)
      expect(result.totals[:total_amount]).to eq(324.0.to_d)
    end

    it "matches SST description case-insensitively" do
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "service tax (sst 8%)", amount: 8.00, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(1)
    end

    it "falls back to deriving taxable amount when no accommodation transactions exist" do
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, category: "tax", description: "Service Tax (SST 8%)", amount: 8.00, posting_date: start_date)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.first[:taxable_amount]).to eq(100.0.to_d)
    end
  end
end
