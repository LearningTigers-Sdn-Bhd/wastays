# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueReport do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  it "aggregates daily rows and source rows from folio transactions" do
    # May 6: 1 booking with accommodation and tax
    booking1 = create(:booking, hotel: hotel, source: "walk_in")
    folio1 = create(:booking_folio, booking: booking1, hotel: hotel)
    create(:folio_transaction, booking_folio: folio1, category: "accommodation", amount: 100, posting_date: Date.new(2026, 5, 6))
    create(:folio_transaction, booking_folio: folio1, category: "tax", amount: 10, posting_date: Date.new(2026, 5, 6))

    # May 7: 1 different booking with accommodation
    booking2 = create(:booking, hotel: hotel, source: "agoda")
    folio2 = create(:booking_folio, booking: booking2, hotel: hotel)
    create(:folio_transaction, booking_folio: folio2, category: "accommodation", amount: 200, posting_date: Date.new(2026, 5, 7))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.rows.size).to eq(2)
    expect(report.source_rows.map { |r| r[:source] }).to include("Walk-in", "Agoda")
    expect(report.totals[:accommodation]).to eq(300.to_d)
    expect(report.totals[:tax]).to eq(10.to_d)
    expect(report.totals[:total_charges]).to eq(310.to_d)
    expect(report.totals[:booking_count]).to eq(2)

    # Check daily rows
    row1 = report.rows.find { |r| r[:date] == Date.new(2026, 5, 6) }
    expect(row1[:accommodation]).to eq(100.to_d)
    expect(row1[:tax]).to eq(10.to_d)
    expect(row1[:booking_count]).to eq(1)

    row2 = report.rows.find { |r| r[:date] == Date.new(2026, 5, 7) }
    expect(row2[:accommodation]).to eq(200.to_d)
    expect(row2[:booking_count]).to eq(1)
  end

  it "includes adjustments/reversals in the totals" do
    booking = create(:booking, hotel: hotel, source: "walk_in")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    tx = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: start_date)

    # Reversal of that transaction on the same day
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
    expect(row[:booking_count]).to eq(1) # Still counted as active because a booking_id had accommodation activity
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

  it "includes agent bank-transfer AR payments in the payment totals and net amount" do
    hotel_corporate_account = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
    create(:ar_payment, hotel: hotel, hotel_corporate_account: hotel_corporate_account, payment_method: "bank_transfer", amount: 400, received_at: start_date)
    # Outside the date range - must not be included
    create(:ar_payment, hotel: hotel, hotel_corporate_account: hotel_corporate_account, payment_method: "bank_transfer", amount: 999, received_at: start_date - 1.day)
    # Different payment method - must not be counted as a bank transfer
    create(:ar_payment, hotel: hotel, hotel_corporate_account: hotel_corporate_account, payment_method: "cheque", amount: 999, received_at: start_date)
    # Different hotel - must not leak in
    other_hotel_account = create(:hotel_corporate_account)
    create(:ar_payment, hotel: other_hotel_account.hotel, hotel_corporate_account: other_hotel_account, payment_method: "bank_transfer", amount: 999, received_at: start_date)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    row = report.rows.find { |r| r[:date] == start_date }
    expect(row[:agent_bank_transfer]).to eq(400.to_d)
    expect(row[:corporate_bank_transfer]).to eq(0.to_d)
    expect(row[:total_payments]).to eq(400.to_d)
    expect(row[:net_amount]).to eq(400.to_d)
    expect(report.totals[:agent_bank_transfer]).to eq(400.to_d)
    expect(report.totals[:total_payments]).to eq(400.to_d)
  end

  it "buckets airline bank transfers as agent transfers, and company/government ones as corporate transfers, without dropping either from the totals" do
    airline_account = create(:hotel_corporate_account, hotel: hotel, account_type: "airline")
    company_account = create(:hotel_corporate_account, hotel: hotel, account_type: "company")
    government_account = create(:hotel_corporate_account, hotel: hotel, account_type: "government")

    create(:ar_payment, hotel: hotel, hotel_corporate_account: airline_account, payment_method: "bank_transfer", amount: 150, received_at: start_date)
    create(:ar_payment, hotel: hotel, hotel_corporate_account: company_account, payment_method: "bank_transfer", amount: 60, received_at: start_date)
    create(:ar_payment, hotel: hotel, hotel_corporate_account: government_account, payment_method: "bank_transfer", amount: 40, received_at: start_date)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    row = report.rows.find { |r| r[:date] == start_date }
    expect(row[:agent_bank_transfer]).to eq(150.to_d)
    expect(row[:corporate_bank_transfer]).to eq(100.to_d)
    expect(row[:total_payments]).to eq(250.to_d)
    expect(row[:net_amount]).to eq(250.to_d)
    expect(report.totals[:agent_bank_transfer]).to eq(150.to_d)
    expect(report.totals[:corporate_bank_transfer]).to eq(100.to_d)
    expect(report.totals[:total_payments]).to eq(250.to_d)
  end
end
