# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::Return do
  it "releases security money and synchronizes the booking workflow status" do
    deposit = create(:deposit, booking: create(:booking, deposit_status: "held"), amount: 100)

    result = described_class.call(deposit: deposit, amount: 100, payment_method: "cash", external_reference: "REL-1")

    expect(result).to be_success
    expect(result.movement).to have_attributes(movement_type: "release", amount: 100.to_d)
    expect(deposit.reload.status).to eq("released")
    expect(deposit.booking.reload.deposit_status).to eq("released")
  end

  it "requires a reason for prepayment refunds and limits them to the available amount" do
    deposit = create(:deposit, :prepayment, amount: 100)

    expect(described_class.call(deposit: deposit, amount: 20).error).to eq("Reason can't be blank.")
    expect(described_class.call(deposit: deposit, amount: 101, reason: "Cancellation").error).to include("exceeds")
  end

  it "records sequential partial refunds in immutable movements" do
    deposit = create(:deposit, :prepayment, amount: 100)

    described_class.call(deposit: deposit, amount: 30, reason: "Reduction")
    described_class.call(deposit: deposit, amount: 20, reason: "Second reduction")

    expect(deposit.reload).to have_attributes(status: "available", refunded_amount: 50.to_d, available_amount: 50.to_d)
  end
end
