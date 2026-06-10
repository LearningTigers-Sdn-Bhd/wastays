# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioLedgerExportService do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.current.beginning_of_month }
  let(:end_date) { Date.current.end_of_month }
  let(:service) { described_class.new(hotel: hotel, start_date: start_date, end_date: end_date) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Alex Ledger") }
  let(:folio) { create(:booking_folio, hotel: hotel, booking: booking) }

  describe "#generate_csv" do
    it "returns CSV string" do
      expect(service.generate_csv).to be_a(String)
      expect(service.generate_csv).to include("Posting Date")
    end
  end

  describe "#generate_xls" do
    it "returns XML string" do
      expect(service.generate_xls).to be_a(String)
      expect(service.generate_xls).to include("Workbook")
    end
  end

  describe "#totals" do
    it "returns a hash of totals" do
      expect(service.totals).to be_a(Hash)
      expect(service.totals).to have_key(:room_revenue)
    end
  end

  describe "General Ledger Code (GL Code) export" do
    it "uses the transaction General Ledger Code (GL Code) snapshot first" do
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "accommodation",
        amount: 100,
        posting_date: start_date,
        gl_code: "SNAP-ROOM")

      csv = CSV.parse(service.generate_csv, headers: true)

      expect(csv.first["General Ledger Code (GL Code)"]).to eq("SNAP-ROOM")
    end

    it "falls back to the hotel General Ledger (GL) mapping for legacy transactions without a General Ledger Code (GL Code) snapshot" do
      hotel.hotel_general_ledger_maps.find_by!(transaction_category: "fb").update!(gl_code: "HOTEL-FB")
      transaction = create(:folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "fb",
        amount: 50,
        posting_date: start_date)
      transaction.update_column(:gl_code, nil)

      csv = CSV.parse(service.generate_csv, headers: true)

      expect(csv.first["General Ledger Code (GL Code)"]).to eq("HOTEL-FB")
    end

    it "uses the unmapped fallback only when no transaction or hotel General Ledger Code (GL Code) exists" do
      transaction = create(:folio_transaction,
        booking_folio: folio,
        transaction_type: :charge,
        category: "other",
        amount: 30,
        posting_date: start_date)
      transaction.update_column(:gl_code, nil)
      hotel.hotel_general_ledger_maps.find_by!(transaction_category: "other").destroy!

      csv = CSV.parse(service.generate_csv, headers: true)

      expect(csv.first["General Ledger Code (GL Code)"]).to eq("9999")
    end
  end
end
