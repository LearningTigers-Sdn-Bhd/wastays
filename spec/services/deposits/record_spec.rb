# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::Record do
  it "records booking security money with an opening hold movement" do
    booking = create(:booking, deposit_status: "pending_at_hotel")
    actor = create(:user, account: booking.hotel.account)

    result = described_class.call(owner: booking, kind: "security", amount: 200, currency: booking.currency,
      payment_method: "cash", actor: actor, external_reference: "SEC-200")

    expect(result).to be_success
    expect(result.deposit).to have_attributes(booking: booking, group_booking: nil, kind: "security", status: "held", amount: 200.to_d)
    expect(result.deposit.deposit_movements.sole).to have_attributes(movement_type: "hold", amount: 200.to_d)
    expect(booking.reload.deposit_status).to eq("held")
  end

  it "records group prepayments without a booking owner" do
    group = create(:group_booking)

    result = described_class.call(owner: group, kind: "prepayment", amount: 500, currency: group.hotel.default_currency,
      payment_method: "bank_transfer")

    expect(result).to be_success
    expect(result.deposit).to have_attributes(group_booking: group, booking: nil, status: "available")
    expect(result.deposit.deposit_movements.sole.movement_type).to eq("receive")
  end

  it "returns the same record for an identical external-reference retry" do
    booking = create(:booking)
    attributes = { owner: booking, kind: "security", amount: 100, currency: booking.currency,
      payment_method: "cash", external_reference: "RETRY-1" }

    first = described_class.call(**attributes)
    second = described_class.call(**attributes)

    expect(second).to be_success
    expect(second.deposit).to eq(first.deposit)
    expect(Deposit.where(external_reference: "RETRY-1").count).to eq(1)
  end

  it "is idempotent for the same operation key" do
    booking = create(:booking)
    attributes = { owner: booking, kind: "prepayment", amount: 80, currency: booking.currency,
      payment_method: "cash", operation_key: "record-once" }

    first = described_class.call(**attributes)
    second = described_class.call(**attributes)

    expect(second).to be_success
    expect(second.deposit).to eq(first.deposit)
    expect(booking.deposits.count).to eq(1)
  end
end
