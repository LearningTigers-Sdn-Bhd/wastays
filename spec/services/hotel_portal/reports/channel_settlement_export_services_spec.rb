# frozen_string_literal: true

require "rails_helper"
require "csv"
require "zip"

RSpec.describe "Channel settlement export services" do
  let(:report) do
    HotelPortal::Reports::ChannelSettlementReport::Result.new(
      start_date: Date.new(2026, 6, 1),
      end_date: Date.new(2026, 6, 30),
      rows: [
        { provider: "booking_com", currency: "MYR", expected_net_amount: 180.to_d, received_amount: 140.to_d, outstanding_amount: 40.to_d, variance_amount: -40.to_d },
        { provider: "agoda", currency: "USD", expected_net_amount: 90.to_d, received_amount: 90.to_d, outstanding_amount: 0.to_d, variance_amount: 0.to_d }
      ],
      currency_totals: [
        { currency: "MYR", expected_net_amount: 180.to_d, received_amount: 140.to_d, outstanding_amount: 40.to_d, variance_amount: -40.to_d },
        { currency: "USD", expected_net_amount: 90.to_d, received_amount: 90.to_d, outstanding_amount: 0.to_d, variance_amount: 0.to_d }
      ],
      totals_by_currency: {
        "MYR" => { currency: "MYR", expected_net_amount: 180.to_d, received_amount: 140.to_d, outstanding_amount: 40.to_d, variance_amount: -40.to_d },
        "USD" => { currency: "USD", expected_net_amount: 90.to_d, received_amount: 90.to_d, outstanding_amount: 0.to_d, variance_amount: 0.to_d }
      }
    )
  end

  it "exports provider rows and separate currency totals as CSV" do
    content = HotelPortal::Reports::ChannelSettlementCsvExportService.new(report: report).generate
    rows = CSV.parse(content.delete_prefix("﻿"))

    expect(rows.first).to eq([ "Provider", "Currency", "Expected Net", "Received", "Outstanding", "Variance" ])
    expect(rows).to include([ "Booking Com", "MYR", "180.00", "140.00", "40.00", "-40.00" ])
    expect(rows).to include([ "TOTAL", "MYR", "180.00", "140.00", "40.00", "-40.00" ])
    expect(rows).to include([ "TOTAL", "USD", "90.00", "90.00", "0.00", "0.00" ])
  end

  it "exports a genuine workbook with one reconciliation sheet per currency" do
    hotel = instance_double(Hotel, name: "Settlement Hotel")
    content = HotelPortal::Reports::ChannelSettlementExcelExportService.new(hotel: hotel, report: report).generate
    xml = []
    Zip::File.open_buffer(StringIO.new(content)) { |archive| archive.each { |entry| xml << entry.get_input_stream.read if entry.name.end_with?(".xml") } }
    text = xml.join.force_encoding(Encoding::UTF_8)

    expect(content).to start_with("PK")
    expect(text).to include("OTA Settlement Report", "MYR Settlements", "USD Settlements", "Booking Com", "Provider reconciliation")
  end
end
