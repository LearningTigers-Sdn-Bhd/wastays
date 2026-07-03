# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupDeposits::Allocate do
  it "posts one child credit without recognizing a second group receipt" do
    group = create(:group_booking)
    booking = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    create(:booking_room, booking: booking)
    folio = create(:booking_folio, booking: booking, hotel: group.hotel, is_primary: true)
    deposit = create(:group_deposit, group_booking: group, hotel: group.hotel, amount: 1_000, currency: folio.currency)

    result = described_class.call(deposit: deposit, booking_folio: folio, amount: 400)

    expect(result).to be_success
    expect(result.allocation.folio_transaction).to have_attributes(
      transaction_type: "payment",
      category: "booking_payment",
      amount: 400.to_d
    )
    expect(deposit.reload.available_amount).to eq(600.to_d)
    expect(deposit.status).to eq("partially_allocated")
  end

  it "prevents allocations above the available amount" do
    deposit = create(:group_deposit, amount: 100)
    booking = create(:booking, hotel: deposit.hotel, group_booking: deposit.group_booking, group_position: 1)
    create(:booking_room, booking: booking)
    folio = create(:booking_folio, booking: booking, hotel: deposit.hotel, is_primary: true, currency: deposit.currency)

    result = described_class.call(deposit: deposit, booking_folio: folio, amount: 101)

    expect(result).not_to be_success
    expect(result.error).to include("exceeds")
  end

  it "refunds only the unallocated portion" do
    deposit = create(:group_deposit, amount: 100)

    result = GroupDeposits::RefundUnallocated.call(deposit: deposit, amount: 40, reason: "Group reduced")
    excessive = GroupDeposits::RefundUnallocated.call(deposit: deposit.reload, amount: 61, reason: "Too much")

    expect(result).to be_success
    expect(deposit.reload).to have_attributes(refunded_amount: 40.to_d, status: "partially_refunded")
    expect(excessive).not_to be_success
  end
end
