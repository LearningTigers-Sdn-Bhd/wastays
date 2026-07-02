# frozen_string_literal: true

require "rails_helper"

RSpec.describe Checkouts::PaymentMethods do
  it "provides four context-specific option labels from one method definition" do
    expect(described_class.settlement_options).to eq([
      [ "Cash", "cash" ],
      [ "Card", "card" ],
      [ "Bank transfer", "bank_transfer" ],
      [ "Manual recovery", "manual" ]
    ])
    expect(described_class.release_options).to eq([
      [ "Cash returned", "cash" ],
      [ "Card released", "card" ],
      [ "Bank transfer", "bank_transfer" ],
      [ "Other/manual", "manual" ]
    ])
  end

  it "maps checkout method values to folio payment sources" do
    expect(described_class.payment_source_for("cash")).to eq("cash")
    expect(described_class.payment_source_for("card")).to eq("card")
    expect(described_class.payment_source_for("bank_transfer")).to eq("bank")
    expect(described_class.payment_source_for("manual")).to eq("gateway")
    expect(described_class.payment_source_for("unknown")).to be_nil
  end
end
