# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::BookingPerformanceReport do
  let(:hotel) { create(:hotel) }

  def bookings = Booking.for_financial_breakdown(hotel, Date.new(2026, 5, 1), Date.new(2026, 5, 31), nil)

  def build(group_by: nil, filters: {}, date_preset: "custom")
    described_class.new(hotel:, bookings:, group_by:, date_preset:, filters:)
  end

  before do
    create(
      :booking, hotel:, source: "direct", fund_collector: "hotel", status: "confirmed",
      payment_status: "captured", currency: "MYR", total_amount: 108,
      tax_lines: [ { "amount" => "8.00" } ], margin_amount: 10, net_amount: 98,
      created_at: Time.zone.local(2026, 5, 6, 12, 0)
    )
    create(
      :booking, hotel:, source: "walk_in", fund_collector: "wastays", status: "completed",
      payment_status: "pending", currency: "USD", total_amount: 50,
      tax_lines: [ { "amount" => "4.00" } ], margin_amount: 5, net_amount: 45,
      created_at: Time.zone.local(2026, 5, 8, 12, 0)
    )
  end

  it "groups by booking date and puts the newest day first" do
    expect(build.groups.map(&:label)).to eq([ "08 May 2026", "06 May 2026" ])
  end

  it "groups a whole year by month" do
    report = build(date_preset: "this_year")

    expect(report.groups.map(&:label)).to eq([ "May 2026" ])
    expect(report.groups.first.count).to eq(2)
  end

  it "puts WAStays before the hotel when it groups by collector" do
    expect(build(group_by: "fund_collector").groups.map(&:label)).to eq([ "WAStays", "Hotel" ])
  end

  it "keeps the totals of each currency apart" do
    totals = build.totals_by_currency

    expect(totals.map { |row| row.fetch(:currency) }).to eq(%w[MYR USD])
    expect(totals.first).to include(booking_count: 1, gross: 108.to_d, taxes: 8.to_d, commission: 10.to_d, net: 98.to_d)
  end

  it "offers every filter value of the unfiltered scope" do
    report = build(filters: { statuses: %w[confirmed] })

    expect(report.rows.size).to eq(1)
    expect(report.filter_options[:statuses].map(&:last)).to include("confirmed", "completed")
  end

  it "matches nothing when a filter holds no value" do
    expect(build(filters: { currencies: [] }).rows).to be_empty
  end

  describe "a booking that an online travel agency took" do
    before do
      BookingSource.seed_defaults!
      BookingSource.reset_registry_cache!
      create(
        :booking, hotel:, source: "bookingcom", fund_collector: "unknown",
        created_at: Time.zone.local(2026, 5, 7, 12, 0)
      )
    end

    it "names the agency as the collector instead of Unknown" do
      row = build.rows.find { |candidate| candidate.source == "bookingcom" }

      expect(row.fund_collector).to eq("ota:booking_com")
      expect(row.fund_collector_label).to eq("Booking.com")
      expect(row.source_label).to eq("Booking.com")
    end

    it "gives the agency its own group, after WAStays and the hotel" do
      groups = build(group_by: "fund_collector").groups

      expect(groups.map(&:label)).to eq([ "WAStays", "Hotel", "Booking.com" ])
    end

    it "offers the agency as a collector filter and filters on it" do
      report = build(group_by: "fund_collector")

      expect(report.filter_options[:fund_collectors]).to include([ "Booking.com", "ota:booking_com" ])
      expect(build(filters: { fund_collectors: %w[ota:booking_com] }).rows.map(&:source)).to eq(%w[bookingcom])
    end

    it "hands the booking back to the hotel once the hotel collects" do
      Booking.where(source: "bookingcom").update_all(fund_collector: "hotel")

      expect(build.rows.map(&:fund_collector_label)).to include("Hotel")
      expect(build.rows.map(&:fund_collector_label)).not_to include("Booking.com")
    end
  end

  it "keeps only the wanted rows in a subset" do
    report = build
    wanted = report.rows.first.booking_id

    expect(report.subset([ wanted ]).rows.map(&:booking_id)).to eq([ wanted ])
  end

  it "regroups the same rows under another grouping" do
    report = build
    regrouped = report.regroup("source")

    expect(regrouped.group_by).to eq("source")
    expect(regrouped.rows.size).to eq(report.rows.size)
    expect(regrouped.groups.map(&:label)).to eq([ "Direct", "Walk-in" ])
  end
end
