# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostCategoryCharge do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { Folios::InitializeForBooking.call(booking: booking, user: user) }

  it "posts a late checkout charge" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "late_checkout_charge",
      amount: 50.0
    )

    expect(result).to be_success
    expect(result.transaction.category).to eq("late_checkout_charge")
    expect(result.transaction.amount).to eq(50.0)
    expect(result.transaction.description).to eq("Late Checkout Charge")
    expect(folio.outstanding_balance).to eq(50.0)
  end

  it "posts an early departure charge with custom description" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "early_departure_charge",
      amount: 100.0,
      description: "Custom Charge"
    )

    expect(result).to be_success
    expect(result.transaction.category).to eq("early_departure_charge")
    expect(result.transaction.amount).to eq(100.0)
    expect(result.transaction.description).to eq("Custom Charge")
  end

  it "fails for invalid category" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "accommodation",
      amount: 50.0
    )

    expect(result).not_to be_success
    expect(result.error).to include("Invalid charge category")
  end

  it "fails for zero amount" do
    result = described_class.call(
      folio: folio,
      user: user,
      category: "late_checkout_charge",
      amount: 0
    )

    expect(result).not_to be_success
    expect(result.error).to include("Charge amount must be greater than zero")
  end
end
