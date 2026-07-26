# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::TransactionActionPolicy do
  let(:user) { create(:user, :superadmin) }
  let(:folio) { create(:booking_folio) }

  def policy_for(transaction)
    described_class.new(transaction: transaction, user: user)
  end

  [
    [ "cash", "cash" ],
    [ "bank", "booking_payment" ],
    [ "card", "gateway_payment" ]
  ].each do |source, category|
    it "allows #{source} staff payments to show Reverse payment" do
      transaction = create(
        :folio_transaction,
        booking_folio: folio,
        transaction_type: "payment",
        category: category,
        amount: 80,
        metadata: { "payment_source" => source }
      )

      policy = policy_for(transaction)

      expect(policy.reverse_allowed?).to be(true)
      expect(policy.action_label).to eq("Reverse payment")
      expect(policy.action_kind).to eq(:reverse)
    end
  end

  it "does not show generic reversal for gateway manual recovery payments" do
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 80,
      metadata: { "payment_source" => "gateway", "source_references" => { "gateway_reference" => "cap_123" }, "manual_recovery" => true }
    )

    policy = policy_for(transaction)

    expect(policy.reverse_allowed?).to be(false)
    expect(policy.action_label).to eq("Refund")
    expect(policy.reverse_error).to eq("Gateway payments must use the payment refund or reconciliation workflow.")
  end

  it "does not show generic reversal for OTA collected payments" do
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 80,
      metadata: { "payment_source" => "ota", "source_references" => { "ota_reference" => "AGD-123" } }
    )

    policy = policy_for(transaction)

    expect(policy.reverse_allowed?).to be(false)
    expect(policy.action_label).to eq("Reconcile")
    expect(policy.reverse_error).to eq("OTA-collected payments must use source reconciliation.")
  end
end
