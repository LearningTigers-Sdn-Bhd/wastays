# frozen_string_literal: true

require "rails_helper"

RSpec.describe Guests::GuestQuery do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let!(:guest1) { create(:guest, name: "Alice", country: "Malaysia", created_by_hotel: hotel) }
  let!(:guest2) { create(:guest, name: "Bob", country: "Singapore") }
  let!(:guest3) { create(:guest, name: "Charlie", country: "Malaysia") }

  before do
    booking1 = create(:booking, hotel: hotel, guest_email: "bob@example.com", guest_name: "Bob", guest_phone: "+6599999999")
    create(:booking_guest, booking: booking1, guest: guest2, is_primary: true)

    booking2 = create(:booking, hotel: other_hotel, guest_email: "charlie@example.com", guest_name: "Charlie", guest_phone: "+6099999999")
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

    it "filters by VIP status tag" do
      guest1.update!(vip: true)
      query = described_class.new(hotel: hotel, params: { tag: "vip" })
      results = query.call
      expect(results).to include(guest1)
      expect(results).not_to include(guest2)
    end

    it "filters by Banned status tag" do
      guest1.update!(blacklisted: true)
      query = described_class.new(hotel: hotel, params: { tag: "banned" })
      results = query.call
      expect(results).to include(guest1)
      expect(results).not_to include(guest2)
    end

    it "filters by Repeat status tag" do
      booking_c = create(:booking, hotel: hotel, status: "completed")
      create(:booking_guest, booking: booking_c, guest: guest2)

      query = described_class.new(hotel: hotel, params: { tag: "repeat" })
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
