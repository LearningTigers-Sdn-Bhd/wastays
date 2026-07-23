# frozen_string_literal: true

require "rails_helper"
require "csv"
require "zip"
require "pdf-reader"

RSpec.describe "Payout export services" do
  let(:hotel) { instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR") }
  let(:upcoming_report) do
    HotelPortal::Reports::PayoutsExportResult.new(
      active_tab: "upcoming",
      upcoming_rows: [
        {
          booking_reference: "WS-ABC",
          checked_out_at: Time.zone.local(2026, 5, 7, 10, 0),
          status: "pending",
          net_amount: 120.to_d
        }
      ],
      processing_rows: [
        {
          period_start: Date.new(2026, 5, 1), period_end: Date.new(2026, 5, 7),
          status: "processing", reference: "PO-PROCESSING", net_amount: 80.to_d
        }
      ],
      paid_rows: [],
      paid_start_date: nil,
      paid_end_date: nil
    )
  end
  let(:paid_report) do
    HotelPortal::Reports::PayoutsExportResult.new(
      active_tab: "paid",
      upcoming_rows: [],
      processing_rows: [],
      paid_rows: [
        {
          period_start: Date.new(2026, 5, 1), period_end: Date.new(2026, 5, 7),
          settled_at: Time.zone.local(2026, 5, 8, 9, 30), status: "paid",
          reference: "PO-1", net_amount: 550.to_d
        }
      ],
      paid_start_date: Date.new(2026, 5, 1),
      paid_end_date: Date.new(2026, 5, 31)
    )
  end

  it "generates a safe CSV for each payout tab" do
    upcoming = HotelPortal::Reports::PayoutsCsvExportService.new(hotel: hotel, report: upcoming_report).generate
    paid = HotelPortal::Reports::PayoutsCsvExportService.new(hotel: hotel, report: paid_report).generate

    expect(upcoming).to start_with("\uFEFF")
    expect(CSV.parse(upcoming.delete_prefix("\uFEFF"))).to include(
      [ "Booking Reference", "Checked Out At", "Status", "Currency", "Net Amount" ],
      [ "WS-ABC", "2026-05-07 10:00", "Pending", "MYR", "120.00" ]
    )
    expect(CSV.parse(paid.delete_prefix("\uFEFF"))).to include(
      [ "Period Start", "Period End", "Settled At", "Status", "Reference", "Currency", "Net Amount" ],
      [ "2026-05-01", "2026-05-07", "2026-05-08 09:30", "Paid", "PO-1", "MYR", "550.00" ]
    )
  end

  it "generates genuine XLSX workbooks with the relevant sections" do
    upcoming = HotelPortal::Reports::PayoutsExcelExportService.new(hotel: hotel, report: upcoming_report).generate
    paid = HotelPortal::Reports::PayoutsExcelExportService.new(hotel: hotel, report: paid_report).generate

    expect(upcoming).to start_with("PK")
    expect(paid).to start_with("PK")
    expect(workbook_text(upcoming)).to include("Weekly Settlements", "Upcoming Settlements", "Processing Batches", "WS-ABC")
    expect(workbook_text(paid)).to include("Weekly Settlements", "Paid History", "PO-1", "MYR")
  end

  it "generates branded PDFs with totals and page numbers" do
    upcoming = HotelPortal::Reports::PayoutsPdfExportService.new(hotel: hotel, report: upcoming_report).generate
    paid = HotelPortal::Reports::PayoutsPdfExportService.new(hotel: hotel, report: paid_report).generate

    expect(pdf_text(upcoming)).to include("WEEKLY SETTLEMENTS", "Upcoming Settlements", "MYR 200.00", "Page 1 of 1")
    expect(pdf_text(paid)).to include("WEEKLY SETTLEMENTS", "Paid History", "PO-1", "MYR 550.00", "Page 1 of 1")
  end

  def workbook_text(content)
    entries = []
    Zip::File.open_buffer(StringIO.new(content)) do |archive|
      archive.each { |entry| entries << entry.get_input_stream.read if entry.name.end_with?(".xml") }
    end
    entries.join.force_encoding(Encoding::UTF_8)
  end

  def pdf_text(content)
    PDF::Reader.new(StringIO.new(content)).pages.map(&:text).join("\n")
  end
end
