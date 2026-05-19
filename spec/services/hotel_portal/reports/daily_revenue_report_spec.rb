# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueReport do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  it "aggregates daily rows and source rows with per-night revenue allocation" do
    # 1-night stay on May 6
    create(:booking, hotel: hotel, status: "confirmed", source: "walk_in",
           total_amount: 100, tourism_tax_applied: true, tourism_tax_amount: 10,
           check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 7))

    # 1-night stay on May 7
    create(:booking, hotel: hotel, status: "completed", source: "agoda",
           total_amount: 200, tourism_tax_applied: false, tourism_tax_amount: 0,
           check_in: Date.new(2026, 5, 7), check_out: Date.new(2026, 5, 8))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.rows.size).to eq(2)
    expect(report.source_rows.map { |r| r[:source] }).to include("Walk-in", "Agoda")
    expect(report.totals[:room_revenue]).to eq(300.to_d)
    expect(report.totals[:tax_amount]).to eq(10.to_d)
    expect(report.totals[:total_revenue]).to eq(310.to_d)
  end

  it "splits multi-night booking revenue across stay dates" do
    # 3-night booking: May 6, 7, 8 — RM900 total = RM300/night
    create(:booking, hotel: hotel, status: "confirmed", source: "walk_in",
           total_amount: 900, tourism_tax_applied: false, tourism_tax_amount: 0,
           check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 9))

    report = described_class.new(hotel: hotel, start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 8)).call

    # Each of the 3 days should show RM300
    report.rows.each do |row|
      expect(row[:room_revenue]).to eq(300.to_d)
    end
    expect(report.totals[:room_revenue]).to eq(900.to_d)
  end
end
