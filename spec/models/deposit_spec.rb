# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposit do
  it "belongs to exactly one booking or group" do
    booking = create(:booking)
    group = create(:group_booking, hotel: booking.hotel)

    expect(build(:deposit, booking: booking, group_booking: group, hotel: booking.hotel)).not_to be_valid
    expect(build(:deposit, booking: nil, group_booking: nil, hotel: booking.hotel)).not_to be_valid
    expect(build(:deposit, booking: booking, group_booking: nil, hotel: booking.hotel)).to be_valid
    expect(build(:deposit, :group_owned, booking: nil, group_booking: group, hotel: booking.hotel)).to be_valid
  end

  it "accepts security and prepayment transaction codes for their matching kinds" do
    security = build(:deposit)
    prepayment = build(:deposit, :prepayment)

    expect(security).to be_valid
    expect(prepayment).to be_valid
    security.transaction_code = prepayment.transaction_code
    expect(security).not_to be_valid
  end

  it "derives applied, returned, and available balances from movements" do
    deposit = create(:deposit, :prepayment, amount: 500)
    create(:deposit_movement, deposit: deposit, movement_type: "refund", amount: 125)

    expect(deposit).to have_attributes(applied_amount: 0.to_d, refunded_amount: 125.to_d, available_amount: 375.to_d)
  end
end
