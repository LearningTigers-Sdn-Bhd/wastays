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

  it "generates XLSX" do
    hotel = instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR")
    content = described_class.new(hotel: hotel, report: report).generate
    expect(content).to start_with("PK")
  end
end
