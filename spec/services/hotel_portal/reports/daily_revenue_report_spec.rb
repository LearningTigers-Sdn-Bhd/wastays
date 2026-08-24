# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueReport do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  it "aggregates daily rows and source rows from charge/adjustment transactions only" do
    booking1 = create(:booking, hotel: hotel, source: "walk_in")
    folio1 = create(:booking_folio, booking: booking1, hotel: hotel)
    create(:folio_transaction, booking_folio: folio1, category: "accommodation", amount: 100, posting_date: Date.new(2026, 5, 6))
    create(:folio_transaction, booking_folio: folio1, category: "tax", amount: 10, posting_date: Date.new(2026, 5, 6))
    create(:folio_transaction, booking_folio: folio1, transaction_type: "payment", category: "cash", amount: 110, posting_date: Date.new(2026, 5, 6))

    booking2 = create(:booking, hotel: hotel, source: "agoda")
    folio2 = create(:booking_folio, booking: booking2, hotel: hotel)
    create(:folio_transaction, booking_folio: folio2, category: "accommodation", amount: 200, posting_date: Date.new(2026, 5, 7))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.rows.size).to eq(2)
    expect(report.source_rows.map { |r| r[:source] }).to include("Walk-in", "Agoda")
    expect(report.totals).to eq(
      booking_count: 2,
      accommodation: 300.to_d,
      other_charges: 0.to_d,
      tax: 10.to_d,
      total_charges: 310.to_d,
      adjustments: 0.to_d,
      net_revenue: 310.to_d
    )

    row1 = report.rows.find { |r| r[:date] == Date.new(2026, 5, 6) }
    expect(row1[:accommodation]).to eq(100.to_d)
    expect(row1[:tax]).to eq(10.to_d)
    expect(row1[:booking_count]).to eq(1)
    expect(row1).not_to have_key(:gateway_payment)
    expect(row1).not_to have_key(:discount)
  end

  it "includes adjustments/reversals in the totals" do
    booking = create(:booking, hotel: hotel, source: "walk_in")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    tx = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: start_date)
    create(:folio_transaction,
           booking_folio: folio,
           transaction_type: "adjustment",
           category: "correction",
           amount: -100,
           posting_date: start_date,
           reversal_of_transaction: tx)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    row = report.rows.find { |r| r[:date] == start_date }
    expect(row[:accommodation]).to eq(100.to_d)
    expect(row[:booking_count]).to eq(1)
    expect(row[:adjustments]).to eq(-100.to_d)
    expect(row[:net_revenue]).to eq(0.to_d)
  end

  it "omits days with no charge/adjustment transactions from daily rows" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: Date.new(2026, 5, 6))

    report = described_class.new(hotel: hotel, start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 10)).call

    expect(report.rows.map { |r| r[:date] }).to eq([ Date.new(2026, 5, 6) ])
  end

  it "does not treat a held security deposit as revenue" do
    booking = create(:booking, hotel: hotel)
    create(:deposit, booking: booking, hotel: hotel, amount: 250, received_at: start_date.in_time_zone)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.rows).to be_empty
    expect(report.totals).to include(
      accommodation: 0.to_d,
      other_charges: 0.to_d,
      tax: 0.to_d,
      total_charges: 0.to_d,
      adjustments: 0.to_d,
      net_revenue: 0.to_d
    )
  end

  it "includes every month in range for the this_year preset, even months with no transactions" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: Date.new(2026, 3, 15))

    report = described_class.new(
      hotel: hotel,
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 12, 31),
      date_preset: "this_year"
    ).call

    expect(report.rows.map { |r| r[:date] }).to eq((1..12).map { |m| Date.new(2026, m, 1) })
    expect(report.rows.find { |r| r[:date] == Date.new(2026, 3, 1) }[:accommodation]).to eq(100.to_d)
    expect(report.rows.find { |r| r[:date] == Date.new(2026, 1, 1) }[:accommodation]).to eq(0)
  end

  it "counts a booking only once per month when it has revenue on multiple nights" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: Date.new(2026, 3, 15))
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: Date.new(2026, 3, 16))

    report = described_class.new(
      hotel: hotel,
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 12, 31),
      date_preset: "this_year"
    ).call

    march = report.rows.find { |row| row[:date] == Date.new(2026, 3, 1) }
    expect(march[:booking_count]).to eq(1)
    expect(march[:accommodation]).to eq(200.to_d)
  end

  it "correctly filters by hotel" do
    other_hotel = create(:hotel)
    booking = create(:booking, hotel: other_hotel, source: "walk_in")
    folio = create(:booking_folio, booking: booking, hotel: other_hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 500, posting_date: start_date)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.totals[:accommodation]).to eq(0)
  end

  it "includes all charge categories (e.g., F&B) in revenue" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, category: "fb", amount: 50, posting_date: start_date)
    create(:folio_transaction, booking_folio: folio, category: "no_show_charge", amount: 75, posting_date: start_date)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 100, posting_date: start_date)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.totals[:accommodation]).to eq(0)
    expect(report.totals[:other_charges]).to eq(125.to_d)
    expect(report.totals[:total_charges]).to eq(125.to_d)
    expect(report.totals[:booking_count]).to eq(1)
  end
end
