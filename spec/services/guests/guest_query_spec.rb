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

    it "shows a VIP marked at this property only" do
      Guests::SetVip.new(guests: guest2, hotel: hotel, vip: true).call

      results = described_class.new(hotel: hotel, params: { tag: "vip" }).call
      expect(results).to include(guest2)

      results = described_class.new(hotel: other_hotel, params: { tag: "vip" }).call
      expect(results).not_to include(guest2)
    end

    it "filters by Blacklisted status tag" do
      guest1.update!(blacklisted: true)
      results = described_class.new(hotel: hotel, params: { tag: "blacklisted" }).call
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

  describe "#tag_counts" do
    it "counts every tab in one query, ignoring the tab that is open" do
      guest1.update!(vip: true, metadata: { "vip_hotel_ids" => [ hotel.id ] })
      guest2.update!(blacklisted: true, metadata: { "blacklisted_hotel_ids" => [ hotel.id ] })

      counts = described_class.new(hotel: hotel, params: { tag: "vip" }).tag_counts

      expect(counts).to eq("all" => 2, "vip" => 1, "repeat" => 0, "blacklisted" => 1)
    end

    it "counts within the search and country filters" do
      counts = described_class.new(hotel: hotel, params: { country: "Singapore" }).tag_counts

      expect(counts["all"]).to eq(1)
    end

    it "counts a repeat guest" do
      booking_c = create(:booking, hotel: hotel, status: "completed")
      create(:booking_guest, booking: booking_c, guest: guest2)

      expect(described_class.new(hotel: hotel, params: {}).tag_counts["repeat"]).to eq(1)
    end
  end

  describe ".repeat_ids" do
    it "returns the guests with more than one booking and a completed stay" do
      booking_c = create(:booking, hotel: hotel, status: "completed")
      create(:booking_guest, booking: booking_c, guest: guest2)

      ids = described_class.repeat_ids([ guest1.id, guest2.id ])

      expect(ids).to contain_exactly(guest2.id)
    end

    it "returns nothing without ids, running no query" do
      expect(described_class.repeat_ids([])).to be_empty
    end
  end

  describe "#country_options" do
    it "returns unique countries for the hotel's guests" do
      query = described_class.new(hotel: hotel, params: {})
      expect(query.country_options).to contain_exactly("Malaysia", "Singapore")
    end
  end
end
