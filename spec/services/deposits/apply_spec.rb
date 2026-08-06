# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::Apply do
  it "applies a booking prepayment to one of its folios" do
    booking = create(:booking, total_amount: 300)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel, currency: booking.currency)
    deposit = create(:deposit, :prepayment, booking: booking, hotel: booking.hotel, amount: 300, currency: booking.currency)

    result = described_class.call(deposit: deposit, booking_folio: folio, amount: 125, operation_key: "apply-1")

    expect(result).to be_success
    expect(result.transaction).to have_attributes(transaction_type: "payment", category: "booking_payment", amount: 125.to_d)
    expect(result.movement).to have_attributes(movement_type: "apply", booking_folio: folio, amount: 125.to_d)
    expect(deposit.reload).to have_attributes(status: "available", available_amount: 175.to_d)
    expect(booking.reload.payment_status).to eq("partial")
  end

  it "allows group-owned security money to target a child folio" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group)
    folio = create(:booking_folio, booking: booking, hotel: group.hotel, currency: booking.currency)
    deposit = create(:deposit, :group_owned, group_booking: group, hotel: group.hotel, amount: 100, currency: folio.currency)

    result = described_class.call(deposit: deposit, booking_folio: folio, amount: 100)

    expect(result).to be_success
    expect(result.transaction).to have_attributes(category: "security_deposit", transaction_code: deposit.transaction_code, gl_code: "2030")
    expect(deposit.reload.status).to eq("settled")
  end

  it "rejects outside folios, currency mismatches, and overspending" do
    deposit = create(:deposit, :prepayment, amount: 100)
    outside = create(:booking_folio)
    wrong_currency = create(:booking_folio, booking: deposit.booking, hotel: deposit.hotel, currency: "USD")

    expect(described_class.call(deposit: deposit, booking_folio: outside, amount: 10).error).to include("owner")
    expect(described_class.call(deposit: deposit, booking_folio: wrong_currency, amount: 10).error).to include("owner")
    expect(described_class.call(deposit: deposit, booking_folio: deposit.booking.booking_folios.create!(hotel: deposit.hotel, currency: deposit.currency, folio_number: "OVER-1", status: "open", opened_at: Time.current), amount: 101).error).to include("exceeds")
  end

  it "is idempotent for the same operation key" do
    deposit = create(:deposit, :prepayment, amount: 100)
    folio = create(:booking_folio, booking: deposit.booking, hotel: deposit.hotel, currency: deposit.currency)

    first = described_class.call(deposit: deposit, booking_folio: folio, amount: 40, operation_key: "same-key")
    second = described_class.call(deposit: deposit, booking_folio: folio, amount: 40, operation_key: "same-key")

    expect(second).to be_success
    expect(second.movement).to eq(first.movement)
    expect(folio.folio_transactions.where(category: "booking_payment").count).to eq(1)
  end
end
