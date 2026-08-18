# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::HotelIdentifierLine do
  describe ".call" do
    it "names every registration and marks missing values" do
      expect(described_class.call(tin: "TIN-123", sst: nil, tourism_tax: "TTX-789"))
        .to eq("TIN: TIN-123 · SST: - · Tourism Tax: TTX-789")
    end
  end

  describe ".for_hotel" do
    it "reads the current registration values from the hotel" do
      hotel = build(:hotel,
        tin: "TIN-123",
        sst_registration_number: "SST-456",
        tourism_tax_registration_number: "TTX-789")

      expect(described_class.for_hotel(hotel))
        .to eq("TIN: TIN-123 · SST: SST-456 · Tourism Tax: TTX-789")
    end
  end
end
