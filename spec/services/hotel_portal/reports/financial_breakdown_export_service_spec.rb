# frozen_string_literal: true

require "rails_helper"
require "csv"
require "zip"
require "pdf-reader"

RSpec.describe "Financial Breakdown export services" do
  let(:hotel) { instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR") }
  let(:report) do
    HotelPortal::Reports::FinancialBreakdownExportResult.new(
      start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 7),
      rows: [ { booking_reference: "WS-ABC", guest_name: "Guest A", status: "confirmed", check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 7), gross: 300, taxes: 20, margin: 30, net: 270, currency: "MYR" } ]
    )
  end

  it "generates safe CSV with totals" do
    content = HotelPortal::Reports::FinancialBreakdownCsvExportService.new(hotel: hotel, report: report).generate
    rows = CSV.parse(content.delete_prefix("\uFEFF"))
    expect(content).to start_with("\uFEFF")
    expect(rows.first).to eq([ "Booking Reference", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Margin", "Net", "Currency" ])
    expect(rows.last).to eq([ "TOTAL", nil, nil, nil, nil, "300.00", "20.00", "30.00", "270.00", "MYR" ])
  end

  it "generates a genuine XLSX workbook" do
    content = HotelPortal::Reports::FinancialBreakdownExcelExportService.new(hotel: hotel, report: report).generate
    expect(content).to start_with("PK")
    xml = []
    Zip::File.open_buffer(StringIO.new(content)) { |archive| archive.each { |entry| xml << entry.get_input_stream.read if entry.name.end_with?(".xml") } }
    expect(xml.join.force_encoding(Encoding::UTF_8)).to include("Financial Breakdown", "Booking Details", "WS-ABC", "Taxes")
  end

  it "generates a branded PDF" do
    content = HotelPortal::Reports::FinancialBreakdownPdfExportService.new(hotel: hotel, report: report).generate
    text = PDF::Reader.new(StringIO.new(content)).pages.map(&:text).join
    expect(text).to include("FINANCIAL BREAKDOWN", "Booking Details", "WS-ABC", "MYR 270.00", "Page 1 of 1")
  end
end
