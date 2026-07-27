# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Payments::RefundSource do
  describe ".options" do
    it "returns labels and keys for each supported refund source" do
      expect(described_class.options).to include(
        [ "Cash", "cash" ],
        [ "Bank Transfer", "bank_transfer" ],
        [ "Card Terminal", "card_terminal" ],
        [ "Gateway", "gateway" ],
        [ "OTA Reconciliation", "ota_reconciliation" ],
        [ "Manual Adjustment", "manual_adjustment" ]
      )
    end
  end

  describe ".valid?" do
    it "checks whether a source key is supported" do
      expect(described_class.valid?("cash")).to be true
      expect(described_class.valid?(:manual_adjustment)).to be true
      expect(described_class.valid?("unknown")).to be false
    end
  end

  describe ".fetch" do
    it "returns a source object for a valid key" do
      source = described_class.fetch("ota_reconciliation")

      expect(source.label).to eq("OTA Reconciliation")
      expect(source.display_label).to eq("OTA reconciliation")
    end

    it "returns nil for an unsupported key" do
      expect(described_class.fetch("unknown")).to be_nil
    end
  end
end
