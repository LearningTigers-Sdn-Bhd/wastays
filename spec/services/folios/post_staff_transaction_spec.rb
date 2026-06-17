# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostStaffTransaction do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

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

  it "posts a selected taxable charge code with active linked taxes" do
    hotel = folio.hotel
    active_tax = create(:hotel_tax, hotel: hotel, name: "SST 8%", rate_type: "percentage", amount: 8, enabled: true)
    inactive_tax = create(:hotel_tax, hotel: hotel, name: "Inactive Fee", rate_type: "flat", amount: 5, enabled: false)
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    code = hotel.transaction_codes.find_by!(system_key: "fnb_revenue")
    code.update!(is_taxable: true)
    code.taxes = [ active_tax, inactive_tax ]

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.category).to eq("fb")
    expect(result.transaction.transaction_code).to eq(code)
    expect(result.tax_transactions.size).to eq(1)

    tax_transaction = result.tax_transactions.first
    expect(tax_transaction.category).to eq("tax")
    expect(tax_transaction.amount).to eq(4.0)
    expect(tax_transaction.metadata["parent_folio_transaction_id"]).to eq(result.transaction.id)
    expect(tax_transaction.metadata["source_transaction_code_id"]).to eq(code.id)
  end

  it "posts selected default charge code categories" do
    Financials::EnsureDefaultTransactionCodes.call(folio.hotel)
    code = folio.hotel.transaction_codes.find_by!(system_key: "parking_revenue")

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "12.00",
      description: "Parking charge"
    )

    expect(result.success?).to be(true)
    expect(result.transaction.category).to eq("parking")
    expect(result.transaction.transaction_code).to eq(code)
  end

  it "does not post tax transactions for non-taxable selected charge codes" do
    code = create(:transaction_code, hotel: folio.hotel, kind: "charge", category: "fb", is_taxable: false)
    code.taxes = [ create(:hotel_tax, hotel: folio.hotel, rate_type: "percentage", amount: 8) ]

    result = described_class.call(
      folio: folio,
      user: user,
      transaction_type: "charge",
      category: nil,
      transaction_code_id: code.id,
      amount: "50.00",
      description: "Restaurant charge"
    )

    expect(result.success?).to be(true)
    expect(result.tax_transactions).to be_nil
    expect(folio.folio_transactions.where(category: "tax")).to be_empty
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
