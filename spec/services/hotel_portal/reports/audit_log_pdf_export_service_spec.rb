# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe HotelPortal::Reports::AuditLogPdfExportService do
  it "renders the shared frame and the audit log body" do
    hotel = create(:hotel, name: "Harbour View Hotel")
    pdf = described_class.new(
      hotel: hotel,
      logs: [],
      period_label: "01 Aug 2026 - 17 Aug 2026",
      prepared_by: "Operations Manager"
    ).generate
    text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

    expect(pdf).to start_with("%PDF")
    expect(text).to include(
      "Harbour View Hotel", "Operation Audit Logs", "PERIOD", "01 Aug 2026 - 17 Aug 2026",
      "PREPARED BY", "Operations Manager", "Audit Entries", "0 entries", "Confidential", "Page 1 of 1"
    )
    expect(text).not_to include("RECORDS")
  end
end
