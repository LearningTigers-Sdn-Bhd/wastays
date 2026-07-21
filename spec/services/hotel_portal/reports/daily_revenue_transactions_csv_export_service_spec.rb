# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::DailyRevenueTransactionsCsvExportService do
  subject(:generated_csv) { described_class.new(rows: [ row ]).generate }

  let(:transaction_time) { Time.zone.local(2026, 7, 21, 9, 26) }
  let(:row) do
    instance_double(
      HotelPortal::Reports::DailyReportChargeRegister::Row,
      posting_date: Date.new(2026, 7, 21),
      transaction_time: transaction_time,
      service_name: "Room Revenue",
      transaction_code: "ROOM",
      booking_reference: "RES-1001",
      folio_number: "ACR-1001/1",
      guest_name: "Sofia Lim",
      room_number: "G01",
      room_type_name: "Garden Chalet",
      relationship_status: "Original",
      signed_amount: 480.to_d,
      tax_amount: 38.40.to_d,
      total_amount: 518.40.to_d,
      currency: "MYR"
    )
  end

  it "exports a BOM-prefixed Revenue Register with analytical columns" do
    parsed = CSV.parse(generated_csv.delete_prefix("\xEF\xBB\xBF"), headers: true)

    expect(generated_csv).to start_with("\xEF\xBB\xBF")
    expect(parsed.headers).to eq(described_class::HEADERS)
    expect(parsed.first.to_h).to include(
      "Posting Date" => "2026-07-21",
      "Posted At" => transaction_time.iso8601,
      "Room Number" => "G01",
      "Room Type" => "Garden Chalet",
      "Base Amount" => "480.00",
      "Tax" => "38.40",
      "Total Amount" => "518.40",
      "Currency" => "MYR"
    )
  end
end
