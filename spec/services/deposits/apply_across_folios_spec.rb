# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::ApplyAcrossFolios do
  let(:group) { create(:group_booking) }
  let(:first_booking) { create(:booking, hotel: group.hotel, group_booking: group, total_amount: 60) }
  let(:second_booking) { create(:booking, hotel: group.hotel, group_booking: group, total_amount: 40) }
  let(:first_folio) { create(:booking_folio, booking: first_booking, hotel: group.hotel, currency: first_booking.currency) }
  let(:second_folio) { create(:booking_folio, booking: second_booking, hotel: group.hotel, currency: second_booking.currency) }
  let(:deposit) do
    create(:deposit, :prepayment, :group_owned, group_booking: group, hotel: group.hotel,
      amount: 100, currency: first_booking.currency)
  end

  before do
    create(:folio_transaction, booking_folio: first_folio, amount: 60, transaction_type: "charge")
    create(:folio_transaction, booking_folio: second_folio, amount: 40, transaction_type: "charge")
  end

  it "applies a group prepayment proportionally across child folios" do
    result = described_class.call(
      deposit: deposit, folios: [ first_folio, second_folio ], amount: 100,
      strategy: "proportional", operation_key: "group-apply"
    )

    expect(result).to be_success
    expect(result.movements.map(&:amount)).to eq([ 60.to_d, 40.to_d ])
    expect(deposit.reload.status).to eq("settled")
  end

  it "supports exact manual allocations" do
    result = described_class.call(
      deposit: deposit, folios: [ first_folio, second_folio ], amount: 75,
      strategy: "manual", manual_amounts: { first_folio.id => 25, second_folio.id => 50 }
    )

    expect(result).to be_success
    expect(result.movements.map(&:amount)).to eq([ 25.to_d, 50.to_d ])
    expect(deposit.reload.available_amount).to eq(25.to_d)
  end

  it "returns the original movements for an idempotent retry" do
    attributes = {
      deposit: deposit, folios: [ first_folio, second_folio ], amount: 100,
      strategy: "outstanding_balance", operation_key: "retry-batch"
    }

    first = described_class.call(**attributes)
    second = described_class.call(**attributes)

    expect(second).to be_success
    expect(second.movements).to eq(first.movements)
    expect(deposit.deposit_movements.movement_type_apply.count).to eq(2)
  end

  it "rolls back every application when one folio is ineligible" do
    outside_folio = create(:booking_folio)

    result = described_class.call(
      deposit: deposit, folios: [ first_folio, outside_folio ], amount: 100,
      strategy: "manual", manual_amounts: { first_folio.id => 50, outside_folio.id => 50 }
    )

    expect(result).not_to be_success
    expect(deposit.deposit_movements.movement_type_apply).to be_empty
    expect(first_folio.folio_transactions.where(category: "booking_payment")).to be_empty
  end
end
