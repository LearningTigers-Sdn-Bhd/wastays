# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe HotelPortal::Reports::RefundReportCsvExportService do
  let(:report) do
    OpenStruct.new(
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      totals: { refund_count: 2, total_amount: 150.00 },
      rows: [
        { date: Date.new(2026, 5, 10), room: "Deluxe", guest_name: "John", booking_reference: "WS-001",
          refund_method: "Bank transfer", reference: "BNK-123", status: "Completed", reason: "Cancelled", refund_amount: 100.00 }
      ]
    )
  end

  it "generates CSV" do
    csv = described_class.new(report: report).generate
    expect(csv).to include("Date,Room,Guest,Booking Ref,Refund Method,Reference,Status,Reason,Refund Amount")
    expect(csv).to include("2026-05-10")
    expect(csv).to include("100.00")
  end
end
