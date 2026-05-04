require "rails_helper"

RSpec.describe Prospect, type: :model do
  describe "stage derivation" do
    it "forces converted when guest is linked" do
      guest = create(:guest)
      prospect = described_class.create!(hotel: create(:hotel), guest: guest, phone_number: "+60123456789", stage: "warm")

      expect(prospect.stage).to eq("converted")
    end

    it "defaults to cold for non-converted prospects" do
      prospect = described_class.create!(hotel: create(:hotel), phone_number: "+60123456789", stage: nil)

      expect(prospect.stage).to eq("cold")
      expect(prospect.last_contact).to be_present
    end
  end

  describe ".lookup_by_phone" do
    it "matches normalized phone variants within the same hotel scope" do
      hotel = create(:hotel)
      prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")

      expect(hotel.prospects.lookup_by_phone("0123456789")).to contain_exactly(prospect)
    end
  end
end
