# frozen_string_literal: true

require "rails_helper"
require "csv"
require "zip"
require "pdf-reader"

RSpec.describe "Booking Performance export services" do
  let(:hotel) do
    instance_double(
      Hotel, name: "Sample Hotel", default_currency: "MYR",
      hotel_time_zone: ActiveSupport::TimeZone["Kuala Lumpur"]
    )
  end
  let(:rows) do
    [
      report_row(
        booking_id: 1, booking_number: "HTL-26100001", confirmation_code: "WS-ABC",
        guest_name: "=Guest A", currency: "MYR", gross: 300.to_d, taxes: 20.to_d,
        commission: 30.to_d, net: 270.to_d, source: "direct", source_label: "Direct"
      ),
      report_row(
        booking_id: 2, booking_number: "HTL-26100002", confirmation_code: "WS-XYZ",
        guest_name: "Guest B", currency: "USD", gross: 100.to_d, taxes: 8.to_d,
        commission: 10.to_d, net: 90.to_d, source: "walk_in", source_label: "Walk-in"
      )
    ]
  end
  let(:report) do
    HotelPortal::Reports::BookingPerformanceReport.new(
      hotel:, rows:, group_by: "source", date_preset: "custom",
      start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 7)
    )
  end

  def report_row(overrides = {})
    HotelPortal::Reports::BookingPerformanceReport::Row.new(**{
      booking_id: 1,
      booked_on: Date.new(2026, 5, 6),
      booking_number: "HTL-26100001",
      confirmation_code: "WS-ABC",
      guest_name: "Guest A",
      status: "confirmed",
      status_label: "Confirmed",
      payment_status: "captured",
      payment_status_label: "Captured",
      check_in: Date.new(2026, 5, 6),
      check_out: Date.new(2026, 5, 7),
      source: "direct",
      source_label: "Direct",
      fund_collector: "wastays",
      fund_collector_label: "WAStays",
      gross: 300.to_d,
      taxes: 20.to_d,
      commission: 30.to_d,
      net: 270.to_d,
      currency: "MYR"
    }.merge(overrides))
  end

  it "keeps sorted totals for each currency" do
    expect(report.totals_by_currency.map { |totals| totals.fetch(:currency) }).to eq(%w[MYR USD])
    expect(report.totals_by_currency.first).to include(gross: 300.to_d, commission: 30.to_d, net: 270.to_d)
    expect(report.totals_by_currency.last).to include(gross: 100.to_d, commission: 10.to_d, net: 90.to_d)
  end

  it "generates safe flat CSV with expanded composites and one total per currency" do
    content = HotelPortal::Reports::FinancialBreakdownCsvExportService.new(hotel:, report:).generate
    parsed = CSV.parse(content.delete_prefix("\uFEFF"))

    expect(content).to start_with("\uFEFF")
    expect(parsed.first).to eq([
      "Booked On", "Booking Number", "Confirmation Code", "Guest Name", "Check In", "Check Out",
      "Source", "Collected By", "Status", "Payment Status", "Gross", "Taxes", "Commission", "Net"
    ])
    expect(parsed[1].values_at(1, 2, 3)).to eq([ "HTL-26100001", "WS-ABC", "'=Guest A" ])
    expect(parsed[2].values_at(0, 10, 11, 12, 13)).to eq([ "TOTAL MYR", "300.00", "20.00", "30.00", "270.00" ])
    expect(parsed.last.values_at(0, 10, 11, 12, 13)).to eq([ "TOTAL USD", "100.00", "8.00", "10.00", "90.00" ])
  end

  it "uses the saved visible columns in CSV" do
    content = HotelPortal::Reports::FinancialBreakdownCsvExportService.new(
      hotel:, report:, visible_columns: %w[booking taxes currency]
    ).generate

    expect(CSV.parse(content.delete_prefix("\uFEFF")).first).to eq(
      [ "Booking Number", "Confirmation Code", "Taxes", "Currency" ]
    )
  end

  it "generates a genuine XLSX workbook partitioned by currency and active group" do
    content = HotelPortal::Reports::FinancialBreakdownExcelExportService.new(hotel:, report:).generate
    expect(content).to start_with("PK")
    xml = []
    Zip::File.open_buffer(StringIO.new(content)) do |archive|
      archive.each { |entry| xml << entry.get_input_stream.read if entry.name.end_with?(".xml") }
    end
    document = xml.join.force_encoding(Encoding::UTF_8)

    expect(document).to include("MYR Booking Performance", "USD Booking Performance", "Direct", "Walk-in")
    expect(document).to include("HTL-26100001", "WS-ABC", "HTL-26100002", "WS-XYZ", "Commission")
  end

  it "generates a branded PDF partitioned by currency with compact composite columns" do
    content = HotelPortal::Reports::FinancialBreakdownPdfExportService.new(
      hotel:, report:, prepared_by: "Sarah Lim"
    ).generate
    pages = PDF::Reader.new(StringIO.new(content)).pages
    text = pages.map(&:text).join

    expect(pages.size).to eq(2)
    expect(text).to include("Booking Performance", "Sarah Lim", "Direct", "Walk-in")
    expect(text).to include("HTL-26100001", "WS-ABC", "HTL-26100002", "WS-XYZ", "Commission")
    expect(text).to include("MYR 270.00", "USD 90.00", "Page 1 of 2", "Page 2 of 2")
  end

  it "keeps one clear empty state in spreadsheet and PDF exports" do
    empty_report = HotelPortal::Reports::BookingPerformanceReport.new(
      hotel:, rows: [], start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 7)
    )
    excel = HotelPortal::Reports::FinancialBreakdownExcelExportService.new(hotel:, report: empty_report).generate
    pdf = HotelPortal::Reports::FinancialBreakdownPdfExportService.new(
      hotel:, report: empty_report, prepared_by: "Sarah Lim"
    ).generate
    excel_xml = []
    Zip::File.open_buffer(StringIO.new(excel)) do |archive|
      archive.each { |entry| excel_xml << entry.get_input_stream.read if entry.name.end_with?(".xml") }
    end

    expect(excel_xml.join.force_encoding(Encoding::UTF_8)).to include("No bookings found for the selected criteria.")
    expect(PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join).to include("No bookings found for the selected criteria.")
  end
end
