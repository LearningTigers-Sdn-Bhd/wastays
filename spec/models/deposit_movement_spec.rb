# frozen_string_literal: true

require "rails_helper"

RSpec.describe DepositMovement do
  it "is immutable after creation" do
    movement = create(:deposit_movement)

    expect(movement.update(reason: "changed")).to be(false)
    expect(movement.errors.full_messages).to include("Deposit movements are immutable")
    expect(movement.destroy).to be(false)
  end

  it "requires folio targets only for applications and reversals" do
    movement = build(:deposit_movement, movement_type: "apply")

    expect(movement).not_to be_valid
    expect(movement.errors.full_messages).to include("Application movements require a folio and folio transaction")
  end

  it "rejects a target folio outside the deposit owner" do
    deposit = create(:deposit, :prepayment)
    other_folio = create(:booking_folio)
    transaction = create(:folio_transaction, booking_folio: other_folio, transaction_type: "payment", category: "booking_payment", amount: 10)
    movement = build(:deposit_movement, deposit: deposit, movement_type: "apply", amount: 10,
      booking_folio: other_folio, folio_transaction: transaction)

    expect(movement).not_to be_valid
    expect(movement.errors[:booking_folio]).to include("must belong to the deposit owner")
  end
end
