# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PaymentSource do
  describe ".options" do
    it "returns labels and keys for each supported source" do
      expect(described_class.options).to include(
        [ "Cash", "cash" ],
        [ "Bank Transfer", "bank" ],
        [ "Card Terminal", "card" ],
        [ "Gateway Manual Recovery", "gateway" ],
        [ "OTA Collected", "ota" ]
      )
    end
  end

  describe ".valid?" do
    it "checks whether a source key is supported" do
      expect(described_class.valid?("cash")).to be true
      expect(described_class.valid?(:gateway)).to be true
      expect(described_class.valid?("unknown")).to be false
    end
  end

  describe ".fetch" do
    it "returns a source object for a valid key" do
      source = described_class.fetch("gateway")

      expect(source.label).to eq("Gateway Manual Recovery")
      expect(source.display_label).to eq("Manual recovery")
      expect(source.system_key).to eq("gateway_manual_recovery_payment")
      expect(source.reference_key).to eq("gateway_reference")
      expect(source.reference_prefix).to eq("Gateway Ref")
      expect(source).to be_required_reference
      expect(source).to be_manual_recovery
      expect(source).not_to be_reversible
    end

    it "returns nil for an unsupported key" do
      expect(described_class.fetch("unknown")).to be_nil
    end
  end

  describe "#transaction_code_for" do
    it "finds the matching hotel transaction code" do
      hotel = create(:hotel)
      transaction_code = hotel.transaction_codes.find_by!(system_key: "cash_payment")

      expect(described_class.fetch("cash").transaction_code_for(hotel)).to eq(transaction_code)
    end
  end
end
