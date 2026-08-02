# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::NightAudits::IndexPresenter do
  let(:hotel) { create(:hotel, default_currency: "MYR") }

  it "builds read-only history rows with status and financial evidence" do
    audit = create(
      :night_audit,
      hotel: hotel,
      business_date: Date.new(2026, 7, 31),
      status: "completed",
      completed_at: Time.zone.local(2026, 8, 1, 2, 15)
    )
    create(
      :night_audit_financial_summary,
      night_audit: audit,
      room_revenue: 500,
      tax_revenue: 40,
      no_show_charges: 20,
      refunds_total: 10
    )

    presenter = described_class.new(
      night_audits: [ audit ],
      status_counts: { "completed" => 1 },
      currency: "MYR"
    )
    row = presenter.rows.sole

    expect(row.business_date).to eq("31 Jul 2026")
    expect(row.status_label).to eq("Completed")
    expect(row.status_variant).to eq(:success)
    expect(row.net_revenue).to eq("RM 550.00")
    expect(presenter.metrics.map { |metric| metric[:value] }).to eq(%w[1 1 0 0])
  end

  it "presents an override close as destructive evidence" do
    audit = build_stubbed(:night_audit, force_closed: true, status: "completed")
    presenter = described_class.new(night_audits: [ audit ], status_counts: { completed: 1 }, currency: "MYR")

    expect(presenter.rows.sole.status_label).to eq("Force closed")
    expect(presenter.rows.sole.status_variant).to eq(:destructive)
  end
end
