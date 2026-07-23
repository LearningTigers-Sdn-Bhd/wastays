# frozen_string_literal: true

require "rails_helper"
require "csv"
require "zip"
require "pdf-reader"

RSpec.describe "Financial Performance export services" do
  let(:hotel) { instance_double(Hotel, name: "Sample Hôtel", default_currency: "MYR") }
  let(:report) do
    HotelPortal::Reports::FinancialPerformanceExportResult.new(
      start_date: Date.new(2026, 5, 6),
      end_date: Date.new(2026, 5, 7),
      totals: { gross: 400.to_d, margin: 40.to_d, net: 360.to_d, booking_count: 2 },
      rows: [
        { date: Date.new(2026, 5, 6), booking_count: 2, gross: 400.to_d, margin: 40.to_d, net: 360.to_d }
      ]
    )
  end

  it "generates a safe, structured CSV" do
    content = HotelPortal::Reports::FinancialPerformanceCsvExportService.new(hotel: hotel, report: report).generate
    rows = CSV.parse(content.delete_prefix("\uFEFF"))

    expect(content).to start_with("\uFEFF")
    expect(rows.first).to eq([ "Date", "Bookings", "Currency", "Gross", "Margin", "Net" ])
    expect(rows.second).to eq([ "2026-05-06", "2", "MYR", "400.00", "40.00", "360.00" ])
    expect(rows.last).to eq([ "TOTAL", "2", "MYR", "400.00", "40.00", "360.00" ])
  end

  it "generates a genuine typed XLSX workbook" do
    content = HotelPortal::Reports::FinancialPerformanceExcelExportService.new(hotel: hotel, report: report).generate

    expect(content).to start_with("PK")
    entries = {}
    Zip::File.open_buffer(StringIO.new(content)) { |archive| archive.each { |entry| entries[entry.name] = entry.get_input_stream.read } }
    text = entries.values_at("xl/sharedStrings.xml", "xl/worksheets/sheet1.xml").compact.join.force_encoding(Encoding::UTF_8)

    expect(text).to include("Financial Summary Report", "Gross Bookings", "Daily Performance", "Sample Hôtel")
    expect(entries.fetch("xl/worksheets/sheet1.xml")).to include("<autoFilter", 'state="frozen"')
  end

  it "generates a branded PDF with reconciled totals" do
    content = HotelPortal::Reports::FinancialPerformancePdfExportService.new(hotel: hotel, report: report).generate
    text = PDF::Reader.new(StringIO.new(content)).pages.map(&:text).join("\n")

    expect(content).to start_with("%PDF")
    expect(text).to include("FINANCIAL SUMMARY REPORT", "Sample Hôtel", "Gross Bookings", "MYR 400.00")
    expect(text).to include("Daily Performance", "06 May 2026", "MYR", "360.00", "Page 1 of 1")
  end

  it "exports valid empty states" do
    empty_report = HotelPortal::Reports::FinancialPerformanceExportResult.new(
      start_date: Date.new(2026, 5, 6),
      end_date: Date.new(2026, 5, 7),
      totals: { gross: 0.to_d, margin: 0.to_d, net: 0.to_d, booking_count: 0 },
      rows: []
    )

    xlsx = HotelPortal::Reports::FinancialPerformanceExcelExportService.new(hotel: hotel, report: empty_report).generate
    pdf = HotelPortal::Reports::FinancialPerformancePdfExportService.new(hotel: hotel, report: empty_report).generate

    expect(xlsx).to include("PK")
    expect(PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join).to include("No financial activity found for this period.")
  end
end
