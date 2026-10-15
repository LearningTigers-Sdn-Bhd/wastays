# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PaymentReference do
  def transaction_with(metadata)
    FolioTransaction.new(id: 1, metadata: metadata)
  end

  it "reads a staff payment's reference from its payment source's key" do
    transaction = transaction_with("payment_source" => "bank", "bank_reference" => "TT-1001", "reference" => "other")

    expect(described_class.value(transaction)).to eq("TT-1001")
  end

  it "reads a reference nested under source_references" do
    transaction = transaction_with("payment_source" => "card", "source_references" => { "card_reference" => "APPR 55" })

    expect(described_class.value(transaction)).to eq("APPR 55")
  end

  it "falls back to the plain reference a check-in payment records" do
    expect(described_class.value(transaction_with("source" => "check_in_payment", "reference" => " RCPT-9 "))).to eq("RCPT-9")
  end

  it "reads the legacy payment_reference key" do
    expect(described_class.value(transaction_with("payment_reference" => "OLD-1"))).to eq("OLD-1")
  end

  it "uses the gateway's external reference for a gateway payment" do
    payment = PaymentTransaction.new(external_reference: "pay_abc")

    expect(described_class.value(transaction_with("payment_transaction_id" => 7), payment_transaction: payment)).to eq("pay_abc")
  end

  it "returns nil when nothing was recorded" do
    expect(described_class.value(transaction_with({}))).to be_nil
    expect(described_class.value(transaction_with("source_references" => "not-a-hash"))).to be_nil
  end

  describe ".by_transaction_id" do
    it "resolves gateway references in one query" do
      payment = create(:payment_transaction, external_reference: "pay_batch")
      gateway = FolioTransaction.new(id: 10, metadata: { "payment_transaction_id" => payment.id })
      staff = FolioTransaction.new(id: 11, metadata: { "payment_source" => "cash", "receipt_reference" => "R-1" })
      blank = FolioTransaction.new(id: 12, metadata: {})

      expect(described_class.by_transaction_id([ gateway, staff, blank ])).to eq(10 => "pay_batch", 11 => "R-1", 12 => nil)
    end
  end
end
