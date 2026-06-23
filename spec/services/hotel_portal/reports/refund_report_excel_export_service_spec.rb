# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe HotelPortal::Reports::RefundReportExcelExportService do
  let(:report) do
    OpenStruct.new(
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      totals: { refund_count: 1, total_amount: 100.00 },
      rows: [
        { date: Date.new(2026, 5, 10), room: "Deluxe", guest_name: "John", booking_reference: "WS-001",
          refund_method: "Bank transfer", reference: "BNK-123", status: "Completed", reason: "Cancelled", refund_amount: 100.00 }
      ]
    )
  end

  it "generates Excel XML" do
    xml = described_class.new(report: report).generate
    expect(xml).to include("Workbook")
    expect(xml).to include("Summary")
    expect(xml).to include("Refund Records")
  end
end
