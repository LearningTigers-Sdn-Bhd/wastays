# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostPenaltyFee do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { Folios::InitializeForBooking.call(booking: booking, user: user) }

  it "posts a late checkout penalty" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "late_checkout_penalty",
      amount: 50.0
    )

    expect(result).to be_success
    expect(result.transaction.category).to eq("late_checkout_penalty")
    expect(result.transaction.amount).to eq(50.0)
    expect(result.transaction.description).to eq("Late Checkout Penalty")
    expect(folio.outstanding_balance).to eq(50.0)
  end

  it "posts an early departure penalty with custom description" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "early_departure_penalty",
      amount: 100.0,
      description: "Custom Penalty"
    )

    expect(result).to be_success
    expect(result.transaction.category).to eq("early_departure_penalty")
    expect(result.transaction.amount).to eq(100.0)
    expect(result.transaction.description).to eq("Custom Penalty")
  end

  it "fails for invalid category" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "accommodation",
      amount: 50.0
    )

    expect(result).not_to be_success
    expect(result.error).to include("Invalid penalty category")
  end

  it "fails for zero amount" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "late_checkout_penalty",
      amount: 0
    )

    expect(result).not_to be_success
    expect(result.error).to include("Penalty amount must be greater than zero")
  end
end
