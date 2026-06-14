# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::RecalculateFinancialSummary, type: :service do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:business_date) { 1.day.ago.to_date }
  let!(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, status: "completed") }
  let!(:summary) { create(:night_audit_financial_summary, night_audit: night_audit, room_revenue: 100.0) }

  before do
    # Create the original transaction that matches the initial summary
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100.0,
      posting_date: business_date,
      metadata: { stay_date: business_date.iso8601 }
    )
  end

  it "recalculates the summary if totals have changed" do
    # Create a NEW transaction for the business date
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking)
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 50.0,
      posting_date: business_date,
      metadata: { stay_date: business_date.iso8601 }
    )

    expect {
      described_class.new(hotel: hotel, business_date: business_date, user: user, reason: "Missing charge found").call
    }.to change { summary.reload.room_revenue }.from(100.0).to(150.0)
  end

  it "does nothing if totals have not changed" do
    expect {
      described_class.new(hotel: hotel, business_date: business_date, user: user, reason: "Routine check").call
    }.not_to change { summary.reload.updated_at }
  end
end
