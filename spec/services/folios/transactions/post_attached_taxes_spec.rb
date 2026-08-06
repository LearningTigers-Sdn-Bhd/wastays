# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::PostAttachedTaxes do
  let(:hotel) { create(:hotel, sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10) }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: user) }
  let(:room_code) { hotel.transaction_codes.find_by(system_key: "room_revenue") }
  let(:late_checkout_code) { hotel.transaction_codes.find_by(system_key: "late_checkout_revenue") }

  before do
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
  end

  def parent_charge(transaction_code:, amount: 100.0, category: "late_checkout_charge")
    Folios::Transactions::InsertTransaction.new(
      booking_folio: folio,
      amount: amount,
      transaction_type: "charge",
      category: category,
      user: user,
      description: "Parent charge",
      options: { transaction_code: transaction_code, system_posting: true }
    ).call.transaction
  end

  def post(overrides = {})
    described_class.call(**{
      folio: folio,
      parent_transaction: parent_charge(transaction_code: late_checkout_code),
      source_transaction_code: late_checkout_code,
      tax_rule_transaction_code: room_code,
      base_amount: 100.0,
      posting_date: hotel.current_business_date,
      user: user,
      basis: "late_checkout_charge",
      options: { system_posting: true }
    }.merge(overrides))
  end

  it "posts a tax line from the tax-rule code's rules" do
    result = post

    expect(result).to be_success
    expect(result.tax_transactions.sole.amount).to eq(8.0)
    expect(result.tax_transactions.sole.category).to eq("tax")
  end

  it "defaults the tax-rule code to the source code" do
    late_checkout_code.update!(is_taxable: true)
    late_checkout_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")

    result = post(tax_rule_transaction_code: nil)

    expect(result.tax_transactions.sole.amount).to eq(10.0)
  end

  it "returns no tax lines when the tax-rule code is not taxable" do
    room_code.update!(is_taxable: false)

    result = post

    expect(result).to be_success
    expect(result.tax_transactions).to eq([])
  end

  it "returns no tax lines when there is no code at all" do
    result = post(source_transaction_code: nil, tax_rule_transaction_code: nil)

    expect(result).to be_success
    expect(result.tax_transactions).to eq([])
  end

  it "records both codes so the ledger explains the inherited rules" do
    metadata = post.tax_transactions.sole.metadata

    expect(metadata["source_transaction_code_id"]).to eq(late_checkout_code.id)
    expect(metadata["tax_rule_source_transaction_code_id"]).to eq(room_code.id)
    expect(metadata["parent_folio_transaction_id"]).to be_present
    expect(metadata.dig("tax_line", "basis")).to eq("late_checkout_charge")
    expect(metadata.dig("tax_line", "basis_amount")).to eq("100.0")
  end

  it "skips a rule that computes to zero" do
    hotel.update!(tourism_tax_amount: 0)
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")

    expect(post.tax_transactions.map(&:amount)).to contain_exactly(8.0)
  end

  it "honours a booking-level exclusion on the tax-rule code" do
    booking.booking_tax_inclusion_overrides.create!(
      hotel: hotel, transaction_code: room_code, primary_tax_key: "sst_tax", action: "exclude"
    )

    expect(post.tax_transactions).to eq([])
  end

  it "fails when a tax line cannot be routed" do
    allow(Folios::Routing::ResolveTargetFolio).to receive(:call)
      .and_return(Folios::Routing::RouteResult.failure("No folio available."))

    result = post

    expect(result).not_to be_success
    expect(result.error).to eq("No folio available.")
  end
end
