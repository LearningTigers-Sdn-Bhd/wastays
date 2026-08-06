# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Charges::PostCategoryCharge do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { Folios::Lifecycle::InitializeForBooking.call(booking: booking, user: user) }

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
    expect(result.transaction.transaction_code.system_key).to eq("late_checkout_revenue")
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
    expect(result.transaction.transaction_code.system_key).to eq("early_departure_revenue")
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

  it "posts a cancellation charge" do
    result = described_class.call(folio: folio, user: user, category: "cancellation_charge", amount: 75.0)

    expect(result).to be_success
    expect(result.transaction.transaction_code.system_key).to eq("cancel_revenue")
  end

  describe "tax treatment" do
    # The stay-event codes carry no tax rules of their own; they bill a room night,
    # so they must post exactly the taxes ROOM posts.
    let(:room_code) { hotel.transaction_codes.find_by(system_key: "room_revenue") }

    before do
      hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    end

    it "attaches ROOM's tax rules to a late checkout charge" do
      result = described_class.call(folio: folio, user: user, category: "late_checkout_charge", amount: 100.0)

      expect(result).to be_success
      expect(result.tax_transactions.map(&:amount)).to contain_exactly(8.0, 10.0)
      expect(result.tax_transactions).to all(have_attributes(category: "tax"))
    end

    it "attaches ROOM's tax rules to an early departure charge" do
      result = described_class.call(folio: folio, user: user, category: "early_departure_charge", amount: 100.0)

      expect(result).to be_success
      expect(result.tax_transactions.map(&:amount)).to contain_exactly(8.0, 10.0)
    end

    it "records the charge's own code as the source and ROOM as the tax-rule source" do
      result = described_class.call(folio: folio, user: user, category: "late_checkout_charge", amount: 100.0)
      metadata = result.tax_transactions.first.metadata

      expect(metadata["source_transaction_code_id"]).to eq(result.transaction.transaction_code_id)
      expect(metadata["tax_rule_source_transaction_code_id"]).to eq(room_code.id)
      expect(metadata.dig("tax_line", "basis")).to eq("late_checkout_charge")
    end

    it "honours a booking-level ROOM tax exclusion" do
      booking.booking_tax_inclusion_overrides.create!(
        hotel: hotel, transaction_code: room_code, primary_tax_key: "sst_tax", action: "exclude"
      )

      result = described_class.call(folio: folio, user: user, category: "late_checkout_charge", amount: 100.0)

      expect(result.tax_transactions.map(&:amount)).to contain_exactly(10.0)
    end

    it "posts no tax when ROOM is not taxable" do
      room_code.update!(is_taxable: false)

      result = described_class.call(folio: folio, user: user, category: "late_checkout_charge", amount: 100.0)

      expect(result).to be_success
      expect(result.tax_transactions).to be_nil
    end

    it "rolls the charge back when a tax line cannot post" do
      allow(Folios::Transactions::PostAttachedTaxes).to receive(:call)
        .and_return(Folios::Transactions::PostAttachedTaxes::Result.failure("Tax routing failed."))

      expect {
        result = described_class.call(folio: folio, user: user, category: "late_checkout_charge", amount: 100.0)
        expect(result).not_to be_success
        expect(result.error).to eq("Tax routing failed.")
      }.not_to change(FolioTransaction, :count)
    end
  end
end
