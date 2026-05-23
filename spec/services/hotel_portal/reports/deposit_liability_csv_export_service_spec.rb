# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DepositLiabilityCsvExportService do
  let(:report) do
    double(
      "DepositLiabilityReportResult",
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
        booking_payment_amount: 300.0,
        earned_amount: 100.0,
        refund_amount: 0.0,
        remaining_liability: 200.0
      }
    )
  end

  subject { described_class.new(report: report) }

  describe "#generate" do
    it "generates a CSV with correct headers and data" do
      csv_content = subject.generate
      rows = CSV.parse(csv_content)

      expect(rows[0]).to eq([ "Guest Name", "Booking Ref", "Stay", "Status", "Rooms", "Folio", "Booking Payment", "Earned", "Refunds", "Remaining Liability", "Latest Payment Date" ])

      data_row = rows[1]
      expect(data_row[0]).to eq("John Doe")
      expect(data_row[1]).to eq("ABC-123")
      expect(data_row[6]).to eq("300.00")
      expect(data_row[9]).to eq("200.00")

      total_row = rows[2]
      expect(total_row[0]).to eq("TOTAL")
      expect(total_row[9]).to eq("200.00")
    end
  end
end
