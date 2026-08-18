# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DepositLiabilityPdfExportService do
  let(:hotel) { create(:hotel) }
  let(:report) do
    double(
      "DepositLiabilityReportResult",
      as_of_date: Date.new(2026, 5, 20),
      rows: [
        {
          guest_name: "John Doe",
          confirmation_token: "ABC-123",
          stay_dates: "20 May 2026 - 22 May 2026",
          booking_status: "confirmed",
          room_details: "Deluxe Room",
          folio_number: "FOL-1",
          booking_payment_amount: 300.0,
          earned_amount: 100.0,
          refund_amount: 0.0,
          remaining_liability: 200.0,
          latest_deposit_posting_date: Time.new(2026, 5, 10, 10, 0, 0)
        }
      ],
      totals: {
        booking_count: 1,
        booking_payment_amount: 300.0,
        earned_amount: 100.0,
        refund_amount: 0.0,
        remaining_liability: 200.0
      }
    )
  end

  subject { described_class.new(hotel: hotel, report: report, prepared_by: "Sarah Lim") }

  describe "#generate" do
    it "generates a PDF content" do
      pdf_content = subject.generate
      expect(pdf_content).to start_with("%PDF-")
    end
  end
end
