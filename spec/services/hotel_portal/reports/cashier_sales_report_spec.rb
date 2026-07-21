# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::CashierSalesReport do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:start_date) { Date.new(2026, 6, 16) }
  let(:end_date) { Date.new(2026, 6, 19) }

  def payment(**attrs)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", **attrs)
  end

  it "splits payments into Advance (booking_payment) vs Settlement (everything else)" do
    advance = payment(category: "booking_payment", amount: 100, posting_date: Date.new(2026, 6, 16))
    settlement = payment(category: "cash", amount: 360, posting_date: Date.new(2026, 6, 17))
    refund = payment(category: "refund", amount: -50, posting_date: Date.new(2026, 6, 18))
    charge = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: Date.new(2026, 6, 17))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.advance_scope).to contain_exactly(advance)
    expect(report.settlement_scope).to contain_exactly(settlement, refund)
    expect(report.advance_scope).not_to include(charge)
  end

  it "excludes Razorpay movements from lists, totals, and summaries" do
    razorpay_advance = create(:payment_transaction, booking: booking, gateway: "razorpay")
    razorpay_settlement = create(:payment_transaction, booking: booking, gateway: "razorpay")
    advance = payment(
      category: "booking_payment",
      amount: 100,
      posting_date: Date.new(2026, 6, 16),
      metadata: { payment_transaction_id: razorpay_advance.id, posting_source: "gateway_payment" }
    )
    settlement = payment(
      category: "gateway_payment",
      amount: 200,
      posting_date: Date.new(2026, 6, 17),
      metadata: { payment_transaction_id: razorpay_settlement.id, posting_source: "gateway_payment" }
    )
    refund = payment(
      category: "refund",
      amount: -50,
      posting_date: Date.new(2026, 6, 18),
      reversal_of_transaction: settlement
    )
    cash = payment(category: "cash", amount: 360, posting_date: Date.new(2026, 6, 17))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.advance_scope).not_to include(advance)
    expect(report.settlement_scope).not_to include(settlement, refund)
    expect(report.settlement_scope).to contain_exactly(cash)
    expect(report.totals).to eq(
      movement_count: 1,
      total_collected: 360.to_d,
      total_refunded: 0.to_d,
      net_cash: 360.to_d
    )
    expect(report.mode_summary_rows).to contain_exactly(include(
      mode: "Cash Payment",
      amount_in: 360.to_d,
      amount_out: 0.to_d,
      balance: 360.to_d
    ))
    expect(report.currency_summary_rows).to contain_exactly(include(
      currency: "MYR",
      amount_in: 360.to_d,
      amount_out: 0.to_d,
      balance: 360.to_d
    ))
    expect(report.grand_total).to eq(amount_in: 360.to_d, amount_out: 0.to_d, balance: 360.to_d)
  end

  it "excludes manually recovered gateway payments but keeps card-terminal payments" do
    gateway_code = hotel.transaction_codes.find_by!(system_key: "gateway_manual_recovery_payment")
    card_code = hotel.transaction_codes.find_by!(system_key: "card_payment")
    gateway_recovery = payment(
      category: "gateway_payment",
      amount: 200,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: gateway_code,
      metadata: { payment_source: "gateway" }
    )
    card_terminal = payment(
      category: "cash",
      amount: 300,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: card_code,
      metadata: { payment_source: "card" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.settlement_scope).not_to include(gateway_recovery)
    expect(report.settlement_scope).to contain_exactly(card_terminal)
    expect(report.grand_total[:balance]).to eq(300.to_d)
  end

  it "classifies a refund from its linked original payment" do
    bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")
    refund_code = hotel.transaction_codes.find_by!(system_key: "refund")
    advance = payment(category: "booking_payment", amount: 100, posting_date: Date.new(2026, 6, 16), transaction_code: bank_code)
    refund = payment(
      category: "refund",
      amount: -40,
      posting_date: Date.new(2026, 6, 18),
      transaction_code: refund_code,
      reversal_of_transaction: advance
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.advance_scope).to contain_exactly(advance, refund)
    bank_advance = report.mode_summary_rows.find { |row| row[:mode] == "Bank Transfer Payment" && row[:section] == "Advance" }
    expect(bank_advance).to include(amount_in: 100.to_d, amount_out: 40.to_d, balance: 60.to_d)
  end

  it "uses refund source metadata as the mode when no original payment is linked" do
    refund = payment(
      category: "refund",
      amount: -25,
      posting_date: Date.new(2026, 6, 18),
      metadata: { refund_source: "cash" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.settlement_scope).to contain_exactly(refund)
    expect(report.mode_by_transaction_id[refund.id]).to eq("Cash Payment")
    cash = report.mode_summary_rows.find { |row| row[:mode] == "Cash Payment" && row[:section] == "Settlement" }
    expect(cash).to include(amount_in: 0.to_d, amount_out: 25.to_d, balance: -25.to_d)
  end

  it "computes movement count, total collected, total refunded, and net cash" do
    payment(category: "booking_payment", amount: 100, posting_date: Date.new(2026, 6, 16))
    payment(category: "cash", amount: 360, posting_date: Date.new(2026, 6, 17))
    payment(category: "refund", amount: -50, posting_date: Date.new(2026, 6, 18))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.totals).to eq(
      movement_count: 3,
      total_collected: 460.to_d,
      total_refunded: 50.to_d,
      net_cash: 410.to_d
    )
  end

  it "scopes by hotel and date range" do
    other_hotel = create(:hotel)
    other_booking = create(:booking, hotel: other_hotel)
    other_folio = create(:booking_folio, booking: other_booking, hotel: other_hotel)
    create(:folio_transaction, booking_folio: other_folio, transaction_type: "payment", category: "cash", amount: 999, posting_date: Date.new(2026, 6, 17))
    payment(category: "cash", amount: 10, posting_date: Date.new(2026, 1, 1))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.totals[:movement_count]).to eq(0)
  end

  it "builds a Cashier Summary grouped by payment mode, split by section, with IN/OUT/Balance" do
    cash_code = hotel.transaction_codes.find_by!(system_key: "cash_payment")
    bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")

    payment(category: "booking_payment", amount: 1_205.20, posting_date: Date.new(2026, 6, 16), transaction_code: bank_code)
    payment(category: "cash", amount: 258.56, posting_date: Date.new(2026, 6, 16), transaction_code: cash_code)
    payment(category: "cash", amount: 1_812.23, posting_date: Date.new(2026, 6, 17), transaction_code: cash_code)
    payment(category: "refund", amount: -50, posting_date: Date.new(2026, 6, 18), transaction_code: cash_code)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    cash_settlement = report.mode_summary_rows.find { |r| r[:mode] == "Cash Payment" && r[:section] == "Settlement" }
    expect(cash_settlement).to include(amount_in: 2_070.79.to_d, amount_out: 50.to_d, balance: 2_020.79.to_d)

    cash_total = report.mode_totals.find { |r| r[:mode] == "Cash Payment" }
    expect(cash_total).to include(amount_in: 2_070.79.to_d, amount_out: 50.to_d, balance: 2_020.79.to_d)

    bank_total = report.mode_totals.find { |r| r[:mode] == "Bank Transfer Payment" }
    expect(bank_total).to include(amount_in: 1_205.20.to_d, amount_out: 0.to_d, balance: 1_205.20.to_d)
  end

  it "builds a Currency Summary grouped by currency and section, plus a grand total" do
    payment(category: "booking_payment", amount: 1_205.20, posting_date: Date.new(2026, 6, 16), currency: "MYR")
    payment(category: "cash", amount: 258.56, posting_date: Date.new(2026, 6, 16), currency: "MYR")
    payment(category: "refund", amount: -50, posting_date: Date.new(2026, 6, 18), currency: "MYR")

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    advance_row = report.currency_summary_rows.find { |r| r[:currency] == "MYR" && r[:section] == "Advance" }
    expect(advance_row).to include(amount_in: 1_205.20.to_d, amount_out: 0.to_d, balance: 1_205.20.to_d)

    settlement_row = report.currency_summary_rows.find { |r| r[:currency] == "MYR" && r[:section] == "Settlement" }
    expect(settlement_row).to include(amount_in: 258.56.to_d, amount_out: 50.to_d, balance: 208.56.to_d)

    expect(report.grand_total).to eq(amount_in: 1_463.76.to_d, amount_out: 50.to_d, balance: 1_413.76.to_d)
  end
end
