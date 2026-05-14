require 'rails_helper'

RSpec.describe BookingEngine::CreateQuote do
  let!(:account) { Account.create!(name: "Test Account", slug: "test-account", status: "active") }
  let!(:hotel) { Hotel.create!(name: "Test Hotel", city: "Kuala Lumpur", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Deluxe", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:check_in) { Date.today }
  let(:check_out) { Date.today + 2.days }
  let(:stay_dates) { (check_in...check_out).to_a }

  before do
    stay_dates.each do |date|
      RoomInventory.create!(room_type: room_type, date: date, quantity: 5, status: "open")
      RoomRate.create!(room_type: room_type, date: date, price: 100, currency: "MYR")
    end
  end

  describe "#call" do
    let(:params) { { hotel_id: hotel.id, room_type_id: room_type.id, check_in: check_in, check_out: check_out, adults: 2 } }

    it "creates a quote and holds inventory" do
      service = described_class.new(params)
      result = service.call

      expect(result.success?).to be true
      expect(result.quote).to be_persisted
      expect(result.quote.booking_quote_items.count).to eq(1)

      # Check inventory held (5 - 1 = 4)
      stay_dates.each do |date|
        expect(room_type.room_inventories.find_by(date: date).quantity).to eq(4)
      end
    end

    it "stores display currency snapshot separately from charge currency" do
      create(:exchange_rate, currency_code: "USD", rate_to_myr: 4.0)
      service = described_class.new(params.merge(display_currency: "USD"))
      result = service.call

      expect(result.success?).to be true
      expect(result.quote.currency).to eq("MYR")
      expect(result.quote.total_amount).to eq(200)
      expect(result.quote.display_currency).to eq("USD")
      expect(result.quote.display_total_amount).to eq(50)
      expect(result.quote.display_exchange_rate).to eq(0.25)
      expect(result.quote.display_rate_source).to eq("managed_fx")
    end

    it "fails if room is no longer available" do
      RoomInventory.update_all(quantity: 0)
      service = described_class.new(params)
      result = service.call

      expect(result.success?).to be false
      expect(result.message).to eq("Room is no longer available for these dates.")
    end

    it "fails with clear error when dates are missing" do
      service = described_class.new(
        hotel_id: hotel.id,
        room_type_id: room_type.id,
        check_in: "",
        check_out: "",
        adults: "",
        children: "",
        room_count: "1"
      )
      result = service.call

      expect(result.success?).to be false
      expect(result.message).to eq("Please select check-in and check-out dates.")
    end
  end
end
