# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::GuestQuery do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let!(:guest1) { create(:guest, name: "Alice", country: "Malaysia", created_by_hotel: hotel) }
  let!(:guest2) { create(:guest, name: "Bob", country: "Singapore") }
  let!(:guest3) { create(:guest, name: "Charlie", country: "Malaysia") }

  before do
    booking1 = create(:booking, hotel: hotel)
    create(:booking_guest, booking: booking1, guest: guest2, is_primary: true)

    booking2 = create(:booking, hotel: other_hotel)
    create(:booking_guest, booking: booking2, guest: guest3, is_primary: true)
  end

  describe "#call" do
    it "returns guests created by the hotel or with bookings at the hotel" do
      query = described_class.new(hotel: hotel, params: {})
      results = query.call

      expect(results).to include(guest1) # created by hotel
      expect(results).to include(guest2) # has booking at hotel
      expect(results).not_to include(guest3) # booking at other hotel
    end

    it "filters by name" do
      query = described_class.new(hotel: hotel, params: { query: "Ali" })
      results = query.call
      expect(results).to include(guest1)
      expect(results).not_to include(guest2)
    end

    it "filters by country" do
      query = described_class.new(hotel: hotel, params: { country: "Singapore" })
      results = query.call
      expect(results).to include(guest2)
      expect(results).not_to include(guest1)
    end
  end

  describe "#country_options" do
    it "returns unique countries for the hotel's guests" do
      query = described_class.new(hotel: hotel, params: {})
      expect(query.country_options).to contain_exactly("Malaysia", "Singapore")
    end
  end
end
