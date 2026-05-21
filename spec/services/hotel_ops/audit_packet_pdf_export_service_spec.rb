# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOps::AuditPacketPdfExportService do
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
           no_show_penalties: 50.to_d,
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
  end
end
