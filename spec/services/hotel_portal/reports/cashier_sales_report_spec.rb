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

  it "summarizes and filters all handling types without changing at-desk totals" do
    cash = payment(category: "cash", amount: 100, posting_date: start_date)
    gateway_payment = create(:payment_transaction, booking:, gateway: "razorpay")
    gateway = payment(
      category: "gateway_payment", amount: 70, posting_date: start_date,
      metadata: { payment_transaction_id: gateway_payment.id, posting_source: "gateway_payment" }
    )

    report = described_class.new(hotel:, start_date:, end_date:).call
    expect(report.transactions).to contain_exactly(cash, gateway)
    expect(report.handling_by_transaction_id).to include(cash.id => "at_desk", gateway.id => "gateway")
    expect(report.totals[:net_cash]).to eq(100.to_d)
    expect(report.all_totals[:net_cash]).to eq(170.to_d)
    expect(report.all_mode_summary_rows.map { |row| row[:handling] }).to contain_exactly("at_desk", "gateway")

    filtered = described_class.new(
      hotel:, start_date:, end_date:, handling: [ "gateway" ], currencies: [ "MYR" ], stages: [ "Settlement" ]
    ).call
    expect(filtered.transactions).to contain_exactly(gateway)
    expect(filtered.all_totals[:net_cash]).to eq(70.to_d)
  end

  it "labels advances, settlements, and refunds with one stage rule" do
    advance = payment(category: "booking_payment", amount: 100, posting_date: Date.new(2026, 6, 16))
    settlement = payment(category: "cash", amount: 360, posting_date: Date.new(2026, 6, 17))
    refund = payment(category: "refund", amount: -50, posting_date: Date.new(2026, 6, 18))
    charge = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: Date.new(2026, 6, 17))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.cash_transactions).to contain_exactly(advance, settlement, refund)
    expect(report.section_by_transaction_id[advance.id]).to eq("Advance")
    expect(report.section_by_transaction_id[settlement.id]).to eq("Settlement")
    expect(report.section_by_transaction_id[refund.id]).to eq("Refund")
    expect(report.cash_transactions).not_to include(charge)
  end


  it "separates canonical OTA credits from cash totals while retaining ordinary advances" do
    source = create(:booking_source, key: "ota_cashier_test", label: "OTA Cashier Test")
    party = create(
      :booking_billing_party,
      booking: booking,
      hotel: hotel,
      party_kind: "ota",
      booking_source: source,
      booking_guest: nil,
      hotel_corporate_account: nil
    )
    ota_folio = create(
      :booking_folio,
      booking: booking,
      hotel: hotel,
      folio_type: "external",
      payer_type: "ota",
      is_primary: false,
      booking_billing_party: party,
      hotel_corporate_account: nil
    )
    ota_code = hotel.transaction_codes.find_by!(system_key: "ota_collected_payment")
    ota_credit = create(
      :folio_transaction,
      booking_folio: ota_folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 90,
      currency: "MYR",
      posting_date: Date.new(2026, 6, 17),
      transaction_code: ota_code,
      metadata: { posting_source: "ota_credit", receipt_policy: "none" }
    )
    bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")
    bank_advance = payment(
      category: "booking_payment",
      amount: 25,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: bank_code
    )
    cash = payment(category: "cash", amount: 10, posting_date: Date.new(2026, 6, 17))

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(ota_credit).to be_ota_collected_credit
    expect(report.non_cash_transactions).to contain_exactly(ota_credit)
    expect(report.non_cash_totals).to eq(
      movement_count: 1,
      total_collected: 90.to_d,
      total_refunded: 0.to_d,
      net_cash: 90.to_d
    )
    expect(report.cash_transactions).to contain_exactly(bank_advance, cash)
    expect(report.section_by_transaction_id[bank_advance.id]).to eq("Advance")
    expect(report.section_by_transaction_id[cash.id]).to eq("Settlement")
    expect(report.totals).to eq(
      movement_count: 2,
      total_collected: 35.to_d,
      total_refunded: 0.to_d,
      net_cash: 35.to_d
    )
    expect(report.mode_totals.map { |row| row[:mode] }).not_to include("OTA Collected Payment")
    expect(report.grand_total[:balance]).to eq(35.to_d)
  end


  it "keeps refunds of canonical OTA credits out of cash amount-out totals" do
    source = create(:booking_source, key: "ota_refund_test", label: "OTA Refund Test")
    party = create(
      :booking_billing_party,
      booking: booking,
      hotel: hotel,
      party_kind: "ota",
      booking_source: source,
      booking_guest: nil,
      hotel_corporate_account: nil
    )
    ota_folio = create(
      :booking_folio,
      booking: booking,
      hotel: hotel,
      folio_type: "external",
      payer_type: "ota",
      is_primary: false,
      booking_billing_party: party,
      hotel_corporate_account: nil
    )
    ota_credit = create(
      :folio_transaction,
      booking_folio: ota_folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 100,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: hotel.transaction_codes.find_by!(system_key: "ota_collected_payment"),
      metadata: { posting_source: "ota_credit", receipt_policy: "none" }
    )
    ota_refund = create(
      :folio_transaction,
      booking_folio: ota_folio,
      transaction_type: "payment",
      category: "refund",
      amount: -25,
      posting_date: Date.new(2026, 6, 18),
      reversal_of_transaction: ota_credit
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.non_cash_transactions).to contain_exactly(ota_credit, ota_refund)
    expect(report.totals[:movement_count]).to eq(0)
    expect(report.grand_total).to eq(amount_in: 0.to_d, amount_out: 0.to_d, balance: 0.to_d)
    expect(report.non_cash_totals).to include(total_collected: 100.to_d, total_refunded: 25.to_d, net_cash: 75.to_d)
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

    expect(report.cash_transactions).not_to include(advance, settlement, refund)
    expect(report.cash_transactions).to contain_exactly(cash)
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

    expect(report.cash_transactions).not_to include(gateway_recovery)
    expect(report.cash_transactions).to contain_exactly(card_terminal)
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

    expect(report.cash_transactions).to contain_exactly(advance, refund)
    expect(report.section_by_transaction_id[refund.id]).to eq("Refund")
    bank_advance = report.mode_summary_rows.find { |row| row[:mode] == "Bank Transfer Payment" && row[:section] == "Advance" }
    bank_refund = report.mode_summary_rows.find { |row| row[:mode] == "Bank Transfer Payment" && row[:section] == "Refund" }
    expect(bank_advance).to include(amount_in: 100.to_d, amount_out: 0.to_d, balance: 100.to_d)
    expect(bank_refund).to include(amount_in: 0.to_d, amount_out: 40.to_d, balance: -40.to_d)
  end

  it "uses refund source metadata as the mode when no original payment is linked" do
    refund = payment(
      category: "refund",
      amount: -25,
      posting_date: Date.new(2026, 6, 18),
      metadata: { refund_source: "cash" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.cash_transactions).to contain_exactly(refund)
    expect(report.mode_by_transaction_id[refund.id]).to eq("Cash Payment")
    cash = report.mode_summary_rows.find { |row| row[:mode] == "Cash Payment" && row[:section] == "Refund" }
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
    cash_refund = report.mode_summary_rows.find { |r| r[:mode] == "Cash Payment" && r[:section] == "Refund" }
    expect(cash_settlement).to include(amount_in: 2_070.79.to_d, amount_out: 0.to_d, balance: 2_070.79.to_d)
    expect(cash_refund).to include(amount_in: 0.to_d, amount_out: 50.to_d, balance: -50.to_d)

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
    expect(settlement_row).to include(amount_in: 258.56.to_d, amount_out: 0.to_d, balance: 258.56.to_d)

    refund_row = report.currency_summary_rows.find { |r| r[:currency] == "MYR" && r[:section] == "Refund" }
    expect(refund_row).to include(amount_in: 0.to_d, amount_out: 50.to_d, balance: -50.to_d)

    expect(report.grand_total).to eq(amount_in: 1_463.76.to_d, amount_out: 50.to_d, balance: 1_413.76.to_d)
  end

  it "filters by time-of-day range across the whole date window" do
    morning = payment(category: "cash", amount: 100, posting_date: Date.new(2026, 6, 17), posted_at: Time.utc(2026, 6, 17, 8, 30))
    afternoon = payment(category: "cash", amount: 200, posting_date: Date.new(2026, 6, 17), posted_at: Time.utc(2026, 6, 17, 15, 0))

    report = described_class.new(
      hotel: hotel, start_date: start_date, end_date: end_date,
      start_time: "08:00", end_time: "12:00"
    ).call

    expect(report.cash_transactions).to contain_exactly(morning)
    expect(report.cash_transactions).not_to include(afternoon)
  end

  it "restricts to explicit transaction_ids when given" do
    kept = payment(category: "cash", amount: 100, posting_date: Date.new(2026, 6, 17))
    dropped = payment(category: "cash", amount: 200, posting_date: Date.new(2026, 6, 17))

    report = described_class.new(
      hotel: hotel, start_date: start_date, end_date: end_date,
      transaction_ids: [ kept.id ]
    ).call

    expect(report.cash_transactions).to contain_exactly(kept)
    expect(report.cash_transactions).not_to include(dropped)
  end
  it "keeps a card-terminal payment that carries the gateway_payment category" do
    card_code = hotel.transaction_codes.find_by!(system_key: "card_payment")
    card_terminal = payment(
      category: "gateway_payment",
      amount: 300,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: card_code,
      metadata: { payment_source: "card", posting_source: "staff" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.cash_transactions).to contain_exactly(card_terminal)
    expect(report.non_cash_transactions).to be_empty
    expect(report.totals[:net_cash]).to eq(300.to_d)
  end

  it "keeps a payment taken on a payment method the hotel defined itself" do
    qr_code = create(
      :transaction_code,
      hotel: hotel, kind: "payment", category: "gateway_payment",
      code: "QR", name: "DuitNow QR", system_key: "qr_payment", system_required: false
    )
    qr_payment = payment(
      category: "gateway_payment",
      amount: 780,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: qr_code,
      metadata: { posting_source: "staff" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.cash_transactions).to contain_exactly(qr_payment)
    expect(report.mode_by_transaction_id[qr_payment.id]).to eq("DuitNow QR")
    expect(report.totals[:net_cash]).to eq(780.to_d)
  end

  it "keeps a payment that manual booking recorded, not treating its link as a gateway charge" do
    direct = create(:payment_transaction, booking: booking, gateway: "manual", event_source: "manual_booking")
    bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")
    staff_transfer = payment(
      category: "booking_payment",
      amount: 500,
      posting_date: Date.new(2026, 6, 17),
      transaction_code: bank_code,
      metadata: { payment_transaction_id: direct.id, posting_source: "gateway_payment" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.cash_transactions).to contain_exactly(staff_transfer)
    expect(report.non_cash_transactions).to be_empty
    expect(report.totals[:net_cash]).to eq(500.to_d)
  end

  it "names the origin of every row no cashier handled, gateway before OTA" do
    ota_code = hotel.transaction_codes.find_by!(system_key: "ota_collected_payment")
    party = create(
      :booking_billing_party, booking: booking, hotel: hotel, party_kind: "ota",
      booking_source: create(:booking_source, key: "ota_origin_test", label: "OTA Origin Test"),
      booking_guest: nil, hotel_corporate_account: nil
    )
    ota_folio = create(
      :booking_folio, booking: booking, hotel: hotel, folio_type: "external", payer_type: "ota",
      is_primary: false, booking_billing_party: party, hotel_corporate_account: nil
    )
    ota_credit = create(
      :folio_transaction, booking_folio: ota_folio, transaction_type: "payment",
      category: "booking_payment", amount: 90, posting_date: Date.new(2026, 6, 17),
      transaction_code: ota_code, metadata: { posting_source: "ota_credit", receipt_policy: "none" }
    )
    online = create(:payment_transaction, booking: booking, gateway: "razorpay")
    gateway_charge = payment(
      category: "gateway_payment", amount: 200, posting_date: Date.new(2026, 6, 17),
      metadata: { payment_transaction_id: online.id, posting_source: "gateway_payment" }
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.non_cash_transactions).to eq([ gateway_charge, ota_credit ])
    expect(report.non_cash_origin_by_transaction_id[gateway_charge.id]).to eq("Gateway")
    expect(report.non_cash_origin_by_transaction_id[ota_credit.id]).to eq("OTA collected")
    expect(report.cash_transactions).to be_empty
  end

  it "orders payment modes the way the hotel ordered its payment methods" do
    PaymentMethods::EnsureDefaults.call(hotel)
    cash_code = hotel.transaction_codes.find_by!(system_key: "cash_payment")
    card_code = hotel.transaction_codes.find_by!(system_key: "card_payment")
    hotel.hotel_payment_methods.find_by!(transaction_code: card_code).update!(position: 0)
    hotel.hotel_payment_methods.find_by!(transaction_code: cash_code).update!(position: 1)

    card = payment(category: "cash", amount: 100, posting_date: Date.new(2026, 6, 17), transaction_code: card_code)
    cash = payment(category: "cash", amount: 200, posting_date: Date.new(2026, 6, 17), transaction_code: cash_code)

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.mode_order.first(2)).to eq([ "Card Payment", "Cash Payment" ])
    expect(report.mode_totals.map { |row| row[:mode] }).to eq([ "Card Payment", "Cash Payment" ])
    expect(report.cash_transactions).to eq([ card, cash ])
  end
end
