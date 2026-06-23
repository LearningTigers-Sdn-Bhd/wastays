# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe HotelPortal::Reports::RefundReportPdfExportService do
  let(:hotel) { create(:hotel, name: "Test Hotel") }
  let(:report) do
    OpenStruct.new(
      start_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 5, 31),
      totals: { refund_count: 1, total_amount: 100.00 },
      rows: [ { date: Date.new(2026, 5, 10), room: "Deluxe", guest_name: "John", booking_reference: "WS-001",
               refund_method: "Bank transfer", reference: "BNK-123", status: "Completed", reason: "Cancelled", refund_amount: 100.00 } ]
    )
  end

  it "generates PDF" do
    pdf = described_class.new(hotel: hotel, report: report).generate
    expect(pdf).to be_a(String)
    expect(pdf).to start_with("%PDF")
  end
end
