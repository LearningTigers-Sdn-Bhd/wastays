# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe "Police report exports" do
  let(:hotel) { create(:hotel, name: "Andaman Cove Resort") }
  let(:report) do
    HotelPortal::Reports::PoliceReport::Result.new(
      start_date: Date.new(2026, 7, 21), end_date: Date.new(2026, 7, 21),
      rows: [ {
        guest_name: "Aiko Tanaka", confirmation_token: "POLICE-123", room_number: "G01",
        document: "Passport P1234567", nationality: "Japan", gender: "Female", date_of_birth: "12 Apr 1990",
        address: "12 Jalan Example", contact: "+60123456789", scheduled_check_in: "21 Jul 2026",
        actual_check_in: "21 Jul 2026\n10:30 PM", scheduled_check_out: "23 Jul 2026",
        actual_check_out: "-", status: "Checked in"
      } ]
    )
  end

  it "exports the police register columns to CSV" do
    csv = HotelPortal::Reports::PoliceReportCsvExportService.new(report:).generate

    expect(CSV.parse(csv.sub("\uFEFF", ""), headers: true).headers).to eq([ "Guest / booking reference", "Room", "Nights stayed", "Nationality", "Gender", "Date of birth", "Address", "Contact", "Scheduled check-in", "Actual check-in", "Scheduled check-out", "Actual check-out", "Status" ])
    expect(csv).to include("Aiko Tanaka", "POLICE-123")
  end

  it "exports a valid PDF titled Daily Police Report" do
    table = HotelPortal::Reports::PoliceReportExportTable.new(report: report)
    pdf = HotelPortal::Reports::PoliceReportPdfExportService.new(hotel:, report:, prepared_by: "Sarah Lim").generate
    text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

    expect(table.pdf_headers).to eq([ "Guest", "Room", "Nights stayed", "Guest details", "Contact", "Scheduled check-in", "Actual check-in", "Scheduled check-out", "Actual check-out", "Status" ])
    expect(HotelPortal::Reports::PoliceReportPdfExportService::COLUMN_WIDTHS).to eq([ 110, 46, 45, 115, 110, 70, 77, 70, 75, 59 ])
    expect(pdf).to start_with("%PDF")
    expect(pdf.bytesize).to be > 500
    expect(text).to include("Police report records", "1 guest stay")
    expect(text).not_to include("GUEST STAYS")
  end

  it "exports a valid Excel workbook" do
    workbook = HotelPortal::Reports::PoliceReportExcelExportService.new(hotel:, report:).generate

    expect(workbook).to start_with("PK")
  end
end
