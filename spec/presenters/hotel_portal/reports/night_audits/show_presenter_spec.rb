# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::NightAudits::ShowPresenter do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:audit) do
    create(
      :night_audit,
      hotel: hotel,
      business_date: Date.new(2026, 7, 31),
      status: "completed",
      started_at: Time.zone.local(2026, 8, 1, 2, 0),
      completed_at: Time.zone.local(2026, 8, 1, 2, 2),
      summary: {
        "arrivals_count" => 4,
        "run_results" => {
          "charges_posted" => {
            "items" => [ { "booking_id" => 42, "amount" => "125.00", "category" => "accommodation" } ]
          }
        }
      },
      blocked_details: { "missing_folio" => [ { "booking_id" => 7, "reason" => "Folio missing" } ] },
      exceptions: { "due_out_detected" => [ { "confirmation_token" => "WA-22", "message" => "Carried forward" } ] }
    )
  end

  subject(:presenter) { described_class.new(night_audit: audit, currency: "MYR") }

  it "summarizes immutable operational and financial evidence" do
    create(
      :night_audit_financial_summary,
      night_audit: audit,
      room_revenue: 500,
      tax_revenue: 40,
      payments_total: 520,
      refunds_total: 10,
      no_show_charges: 20
    )

    expect(presenter.caption).to include("31 Jul 2026", "Completed")
    expect(presenter.alert).to include(tone: :success, title: "Business date closed")
    expect(presenter.audit_metrics.map { |metric| metric[:value] }).to eq(%w[4 0 0 0 1 1])
    expect(presenter.financial_metrics.last).to include(label: "Net revenue", value: "RM 550.00")
    expect(presenter.export_available?).to be(true)
  end

  it "normalizes result and exception rows for report tables" do
    result = presenter.result_rows.sole
    issues = presenter.issue_rows

    expect(result).to have_attributes(result: "Charges posted", reference: 42, amount: "RM 125.00", variant: :success)
    expect(issues.map(&:severity)).to contain_exactly("Blocker", "Warning")
    expect(issues.map(&:reference)).to contain_exactly(7, "WA-22")
  end

  it "does not offer an audit packet for an incomplete run" do
    audit.update!(status: "blocked")

    expect(presenter.status_variant).to eq(:warning)
    expect(presenter.export_available?).to be(false)
  end

  it "presents adjustments as evidence without exposing workflow actions" do
    booking = create(:booking, hotel: hotel, guest_name: "Aina Yusuf", confirmation_token: "WA-81")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    adjustment = create(
      :folio_transaction,
      booking_folio: folio,
      user: audit.performed_by_user,
      transaction_type: "adjustment",
      category: "adjustment",
      amount: -25,
      metadata: { "reason" => "Rate correction" }
    )
    report = described_class.new(night_audit: audit, adjustments: [ adjustment ], currency: "MYR")

    expect(report.adjustment_rows.sole).to have_attributes(
      guest: "Aina Yusuf",
      reference: "WA-81",
      category: "Adjustment",
      amount: "-RM 25.00",
      reason: "Rate correction"
    )
  end
end
