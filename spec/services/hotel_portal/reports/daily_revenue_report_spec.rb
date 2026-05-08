# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueReport do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  it "aggregates daily rows and source rows" do
    create(:booking, hotel: hotel, status: "confirmed", source: "walk_in", total_amount: 100, tourism_tax_applied: true, tourism_tax_amount: 10, created_at: Time.zone.local(2026, 5, 6, 9, 0))
    create(:booking, hotel: hotel, status: "completed", source: "agoda", total_amount: 200, tourism_tax_applied: false, tourism_tax_amount: 0, created_at: Time.zone.local(2026, 5, 7, 11, 0))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.rows.size).to eq(2)
    expect(report.source_rows.map { |r| r[:source] }).to include("Walk-in", "Agoda")
    expect(report.totals[:room_revenue]).to eq(300.to_d)
    expect(report.totals[:tax_amount]).to eq(10.to_d)
    expect(report.totals[:total_revenue]).to eq(310.to_d)
  end
end
