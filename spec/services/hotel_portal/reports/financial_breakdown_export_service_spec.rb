# frozen_string_literal: true

require "rails_helper"
require "csv"
require "zip"
require "pdf-reader"

RSpec.describe "Financial Breakdown export services" do
  let(:hotel) do
    instance_double(
      Hotel, name: "Sample Hotel", default_currency: "MYR",
      hotel_time_zone: ActiveSupport::TimeZone["Kuala Lumpur"]
    )
  end
  let(:report) do
    HotelPortal::Reports::FinancialBreakdownExportResult.new(
      start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 7),
      rows: [
        {
          booking_number: "HTL-26100001", confirmation_code: "WS-ABC", guest_name: "=Guest A",
          status: "confirmed", check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 7),
          gross: 300, taxes: 20, margin: 30, net: 270, currency: "MYR"
        },
        {
          booking_number: "HTL-26100002", confirmation_code: "WS-XYZ", guest_name: "Guest B",
          status: "completed", check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 7),
          gross: 100, taxes: 8, margin: 10, net: 90, currency: "USD"
        }
      ]
    )
  end

  it "keeps sorted totals for each currency" do
    expect(report.currency_totals.map { |totals| totals.fetch(:currency) }).to eq(%w[MYR USD])
    expect(report.totals_by_currency.fetch("MYR")).to include(gross: 300.to_d, margin: 30.to_d, net: 270.to_d)
    expect(report.totals_by_currency.fetch("USD")).to include(gross: 100.to_d, margin: 10.to_d, net: 90.to_d)
  end

  it "generates safe CSV with identifiers and one total per currency" do
    content = HotelPortal::Reports::FinancialBreakdownCsvExportService.new(hotel: hotel, report: report).generate
    rows = CSV.parse(content.delete_prefix("\uFEFF"))
    expect(content).to start_with("\uFEFF")
    expect(rows.first).to eq([ "Booking Number", "Confirmation Code", "Guest Name", "Status", "Check In", "Check Out", "Gross", "Taxes", "Commission", "Net", "Currency" ])
    expect(rows[1].values_at(0, 1, 2)).to eq([ "HTL-26100001", "WS-ABC", "'=Guest A" ])
    expect(rows[2]).to eq([ "TOTAL", nil, nil, nil, nil, nil, "300.00", "20.00", "30.00", "270.00", "MYR" ])
    expect(rows.last).to eq([ "TOTAL", nil, nil, nil, nil, nil, "100.00", "8.00", "10.00", "90.00", "USD" ])
  end

  it "generates a genuine XLSX workbook with one sheet per currency" do
    content = HotelPortal::Reports::FinancialBreakdownExcelExportService.new(hotel: hotel, report: report).generate
    expect(content).to start_with("PK")
    xml = []
    Zip::File.open_buffer(StringIO.new(content)) { |archive| archive.each { |entry| xml << entry.get_input_stream.read if entry.name.end_with?(".xml") } }
    document = xml.join.force_encoding(Encoding::UTF_8)
    expect(document).to include("MYR Financial Breakdown", "USD Financial Breakdown", "Booking Details")
    expect(document).to include("HTL-26100001", "WS-ABC", "HTL-26100002", "WS-XYZ", "Commission")
  end

  it "generates a branded PDF with one page per currency and stacked identifiers" do
    content = HotelPortal::Reports::FinancialBreakdownPdfExportService.new(hotel: hotel, report: report, prepared_by: "Sarah Lim").generate
    pages = PDF::Reader.new(StringIO.new(content)).pages
    text = pages.map(&:text).join
    expect(pages.size).to eq(2)
    expect(text).to include("Financial Breakdown", "Sarah Lim", "MYR Booking Details", "USD Booking Details")
    expect(text).to include("HTL-26100001", "WS-ABC", "HTL-26100002", "WS-XYZ", "Commission")
    expect(text).to include("MYR 270.00", "USD 90.00", "Page 1 of 2", "Page 2 of 2")
  end

  it "keeps one clear empty state in spreadsheet and PDF exports" do
    empty_report = HotelPortal::Reports::FinancialBreakdownExportResult.new(
      start_date: Date.new(2026, 5, 6),
      end_date: Date.new(2026, 5, 7),
      rows: []
    )
    excel = HotelPortal::Reports::FinancialBreakdownExcelExportService.new(hotel: hotel, report: empty_report).generate
    pdf = HotelPortal::Reports::FinancialBreakdownPdfExportService.new(
      hotel: hotel,
      report: empty_report,
      prepared_by: "Sarah Lim"
    ).generate
    excel_xml = []
    Zip::File.open_buffer(StringIO.new(excel)) do |archive|
      archive.each { |entry| excel_xml << entry.get_input_stream.read if entry.name.end_with?(".xml") }
    end

    expect(excel_xml.join.force_encoding(Encoding::UTF_8)).to include("No bookings found for the selected criteria.")
    expect(PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join).to include("No bookings found for the selected criteria.")
  end
end
