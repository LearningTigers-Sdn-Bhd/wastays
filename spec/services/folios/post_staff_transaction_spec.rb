# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostStaffTransaction do
  let(:folio) { create(:booking_folio) }
  let(:user) { create(:user, :superadmin) }

  it "posts a cash payment" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "100.00",
      description: "Cash payment"
    )

    expect(result.success?).to be(true)
    transaction = result.transaction
    expect(transaction.transaction_type).to eq("payment")
    expect(transaction.category).to eq("cash")
    expect(transaction.amount).to eq(100.0)
    expect(transaction.metadata["posting_source"]).to eq("staff")
    expect(transaction.metadata["posted_by_user_id"]).to eq(user.id)
  end

  it "posts an other charge" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "other",
      amount: "25.00",
      description: "Lost key charge"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("charge")
    expect(result.transaction.category).to eq("other")
    expect(result.transaction.amount).to eq(25.0)
  end

  it "posts an adjustment" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "adjustment",
      category: "write_off",
      amount: "-10.00",
      description: "Write off balance"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("adjustment")
    expect(result.transaction.category).to eq("write_off")
    expect(result.transaction.amount).to eq(-10.0)
  end

  it "records refunds as negative payments" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "refund",
      amount: "50.00",
      description: "Refund credit balance"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.transaction_type).to eq("payment")
    expect(result.transaction.category).to eq("refund")
    expect(result.transaction.amount).to eq(-50.0)
  end

  it "rejects manual accommodation charges" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "accommodation",
      amount: "100.00",
      description: "Manual room charge"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Category is not allowed for charge transactions.")
  end

  it "rejects gateway payment categories" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: "100.00",
      description: "Gateway payment"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Category is not allowed for payment transactions.")
  end

  it "rejects blank descriptions" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "100.00",
      description: ""
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Description can't be blank.")
  end

  it "rejects negative cash payment amounts" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "payment",
      category: "cash",
      amount: "-100.00",
      description: "Cash payment"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Amount must be greater than zero.")
  end

  it "rejects negative charge amounts" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: "other",
      amount: "-25.00",
      description: "Other charge"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Amount must be greater than zero.")
  end

  it "rejects zero adjustment amounts" do
    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "adjustment",
      category: "adjustment",
      amount: "0.00",
      description: "No-op adjustment"
    )

    expect(result.success?).to be(false)
    expect(result.error).to eq("Amount can't be zero.")
  end
end
