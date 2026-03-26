require 'rails_helper'

RSpec.describe BookingEngine::AvailabilityService do
  let!(:account) { Account.create!(name: "Test Account", slug: "test-account", status: "active") }
  let!(:hotel) { Hotel.create!(name: "Test Hotel", city: "Kuala Lumpur", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2, base_price: 100) }
  
  let(:check_in) { Date.today }
  let(:check_out) { Date.today + 2.days }
  let(:stay_dates) { (check_in...check_out).to_a }

  before do
    stay_dates.each do |date|
      RoomInventory.create!(room_type: room_type, date: date, quantity: 5, status: "open")
      RoomRate.create!(room_type: room_type, date: date, price: 100, currency: "MYR")
    end
  end

  describe "#find_available_hotels" do
    it "returns the hotel when city and availability match" do
      service = described_class.new(city: "Kuala Lumpur", check_in: check_in, check_out: check_out, adults: 2)
      expect(service.find_available_hotels).to include(hotel)
    end

    it "does not return the hotel if city does not match" do
      service = described_class.new(city: "Singapore", check_in: check_in, check_out: check_out, adults: 2)
      expect(service.find_available_hotels).not_to include(hotel)
    end

    it "does not return the hotel if no inventory" do
      RoomInventory.delete_all
      service = described_class.new(city: "Kuala Lumpur", check_in: check_in, check_out: check_out, adults: 2)
      expect(service.find_available_hotels).not_to include(hotel)
    end
  end

  describe "#available_rooms_for_hotel" do
    it "returns room type if availability exists" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.available_rooms_for_hotel(hotel)).to include(room_type)
    end

    it "returns empty if quantity is zero" do
      RoomInventory.update_all(quantity: 0)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end

    it "returns empty if status is closed" do
      RoomInventory.update_all(status: 'closed')
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end
  end

  describe "#calculate_total_price" do
    it "sums up rates correctly" do
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(200.0) # 100 * 2 nights
    end
  end
end
