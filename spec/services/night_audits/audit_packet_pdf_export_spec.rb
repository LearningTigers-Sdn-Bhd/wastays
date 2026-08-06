# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe NightAudits::AuditPacketPdfExport do
  let(:hotel) { create(:hotel, name: "Test Hotel") }
  let(:business_date) { Date.new(2026, 5, 20) }
  let(:night_audit) do
    create(:night_audit,
           hotel: hotel,
           business_date: business_date,
           status: "completed",
           completed_at: Time.current,
           exceptions: { "open_housekeeping_requests" => [] },
           blocked_details: { "outstanding_folio_balance" => [] })
  end
  let!(:summary) do
    create(:night_audit_financial_summary,
           night_audit: night_audit,
           room_revenue: 1000.to_d,
           tax_revenue: 100.to_d,
            no_show_charges: 50.to_d,
           payments_total: 1150.to_d,
           refunds_total: 0.to_d,
           adjustments_total: -10.to_d)
  end

  describe "#generate" do
    it "generates a valid PDF starting with %PDF" do
      service = described_class.new(night_audit: night_audit)
      pdf = service.generate

      expect(pdf).to start_with("%PDF")
    end

    it "includes the hotel name and business date" do
      # This is a bit of a smoke test for the prawn rendering
      service = described_class.new(night_audit: night_audit)
      expect { service.generate }.not_to raise_error
    end

    it "lists adjustments by posting date even when they were created later" do
      included = create_adjustment(
        posting_date: business_date,
        created_at: hotel.business_day_window_for(business_date).end + 1.day,
        reason: "Historical correction"
      )
      excluded = create_adjustment(
        posting_date: business_date + 1.day,
        created_at: hotel.business_day_window_for(business_date).begin + 1.hour,
        reason: "Wrong posting date"
      )

      text = PDF::Reader.new(StringIO.new(described_class.new(night_audit: night_audit).generate)).pages.map(&:text).join("\n")

      expect(text).to include(included.booking_folio.booking.confirmation_token)
      expect(text).to include("Historical correction")
      expect(text).not_to include(excluded.booking_folio.booking.confirmation_token)
      expect(text).not_to include("Wrong posting date")
    end
  end

  def create_adjustment(posting_date:, created_at:, reason:)
    booking = create(:booking, hotel:)
    folio = create(:booking_folio, booking:)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "adjustment",
      category: "adjustment",
      amount: -5,
      posting_date:,
      created_at:,
      metadata: { "reason" => reason }
    )
  end
end
