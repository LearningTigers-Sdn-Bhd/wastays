# frozen_string_literal: true

require "rails_helper"

RSpec.describe BankCatalog do
  describe ".options" do
    it "returns bank names as select-menu label and value pairs" do
      expect(described_class.options).to include([ "Maybank", "Maybank" ], [ "CIMB", "CIMB" ])
    end

    it "preserves a saved bank that is not in the standard list" do
      expect(described_class.options(current: "Legacy Bank")).to include([ "Legacy Bank", "Legacy Bank" ])
    end

    it "does not duplicate a standard saved bank" do
      expect(described_class.options(current: "Maybank").count([ "Maybank", "Maybank" ])).to eq(1)
    end
  end
end
