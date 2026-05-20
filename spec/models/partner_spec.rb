# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Partner, type: :model do
  let(:hotel) { create(:hotel) }

  describe "code generation" do
    it "generates a code with first 3 letters of name and 3 random numbers" do
      partner = Partner.create!(hotel: hotel, name: "Booking.com")
      expect(partner.code).to match(/\ABOO\d{3}\z/)
    end

    it "pads with X if name is shorter than 3 characters" do
      partner = Partner.create!(hotel: hotel, name: "Go")
      expect(partner.code).to match(/\AGOX\d{3}\z/)
    end

    it "handles alphanumeric characters only" do
      partner = Partner.create!(hotel: hotel, name: "B&B")
      expect(partner.code).to match(/\ABBX\d{3}\z/)
    end

    it "ensures code uniqueness within a hotel" do
      # Mock rand to ensure same numbers are generated
      allow_any_instance_of(Object).to receive(:rand).and_return(123, 123, 456)
      
      partner1 = Partner.create!(hotel: hotel, name: "Alpha")
      partner2 = Partner.create!(hotel: hotel, name: "Alpha")
      
      expect(partner1.code).to eq("ALP123")
      expect(partner2.code).to eq("ALP456")
    end
  end
end
