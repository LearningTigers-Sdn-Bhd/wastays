require 'rails_helper'

RSpec.describe BookingEngine::AvailabilityService do
  let!(:account) { Account.create!(name: "Test Account", slug: "test-account", status: "active") }
  let!(:hotel) { Hotel.create!(name: "Test Hotel", city: "Kuala Lumpur", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:check_in) { Date.today }
  let(:check_out) { Date.today + 2.days }
  let(:stay_dates) { (check_in...check_out).to_a }

  before do
    # Ensure room_type has its auto-created Standard Rate plan
    standard_plan = room_type.rate_plans.first
    stay_dates.each do |date|
      RoomInventory.create!(room_type: room_type, date: date, quantity: 5, status: "open")
      # Create rates for both nil plan and standard plan
      RoomRate.create!(room_type: room_type, rate_plan: nil, date: date, price: 100, currency: "MYR")
      RoomRate.create!(room_type: room_type, rate_plan: standard_plan, date: date, price: 100, currency: "MYR")
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

    it "falls back to room_type.base_price if RoomRate is missing" do
      RoomRate.delete_all
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(200.0) # 100 (base) * 2 nights
    end

    it "fails if both RoomRate and base_price are missing" do
      RoomRate.delete_all
      room_type.update_columns(base_price: nil)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(0)
    end

    it "respects stop_sell even if base_price exists" do
      # Apply stop sell to all rates (including those for Standard Rate plan)
      RoomRate.update_all(stop_sell: true)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(0)
    end

    it "respects stop_sell on Standard Rate Plan when calculating base rate fallback" do
      # Only standard plan is stop sell, nil plan has no RoomRate record
      RoomRate.where(rate_plan_id: nil).delete_all
      RoomRate.where(rate_plan_id: room_type.rate_plans.first.id).update_all(stop_sell: true)

      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(0)
      expect(service.available_rooms_for_hotel(hotel)).to be_empty
    end

    it "ignores corporate_price even if available" do
      RoomRate.update_all(corporate_price: 80)
      service = described_class.new(check_in: check_in, check_out: check_out, adults: 2)
      expect(service.calculate_total_price(room_type)).to eq(200.0) # 100 * 2 nights
    end
  end

  describe "#available_rooms_for_hotel with restrictions" do
    let(:tomorrow) { Date.current + 1.day }
    let(:check_out_date) { tomorrow + 1.day } # 1 night stay

    it "returns empty when allow_restricted is false for min stay" do
      RoomRate.update_all(min_stay: 3)
      service = described_class.new(params: { check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2 })
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: false)).to be_empty
    end

    it "returns room type when allow_restricted is true for min stay" do
      RoomRate.update_all(min_stay: 3)
      service = described_class.new(params: { check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2 })
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: true)).to include(room_type)
      expect(service.stay_restriction_error_message(room_type)).to include("Minimum stay is 3 night(s)")
    end

    it "returns empty when allow_restricted is false for CTA" do
      RoomRate.update_all(min_stay: nil, closed_to_arrival: true)
      service = described_class.new(params: { check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2 })
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: false)).to be_empty
    end

    it "returns room type when allow_restricted is true for CTA" do
      RoomRate.update_all(min_stay: nil, closed_to_arrival: true)
      service = described_class.new(params: { check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2 })
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: true)).to include(room_type)
      expect(service.stay_restriction_error_message(room_type)).to include("Check-in is not allowed")
    end

    it "returns empty when allow_restricted is false for CTD" do
      RoomRate.update_all(min_stay: nil, closed_to_departure: true)
      service = described_class.new(params: { check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2 })
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: false)).to be_empty
    end

    it "returns room type when allow_restricted is true for CTD" do
      RoomRate.update_all(min_stay: nil, closed_to_departure: true)
      service = described_class.new(params: { check_in: tomorrow.to_s, check_out: check_out_date.to_s, adults: 2 })
      expect(service.available_rooms_for_hotel(hotel, allow_restricted: true)).to include(room_type)
      expect(service.stay_restriction_error_message(room_type)).to include("Check-out is not allowed")
    end
  end
end
