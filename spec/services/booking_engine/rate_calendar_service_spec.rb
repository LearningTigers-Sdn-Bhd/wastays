require "rails_helper"

RSpec.describe BookingEngine::RateCalendarService do
  let!(:account)   { Account.create!(name: "Test", slug: "test-rc", status: "active") }
  let!(:hotel)     { Hotel.create!(sell_mode: "per_room", name: "RC Hotel", city: "KL", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Standard", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:today) { Date.current }

  def seed_day(date, price: 200.0, quantity: 5, status: "open")
    RoomRate.create!(room_type: room_type, rate_plan: room_type.standard_rate_plan, date: date, price: price, currency: "MYR")
    RoomInventory.create!(room_type: room_type, date: date, quantity: quantity, status: status)
  end

  def call(start_date: today, end_date: today + 6, room_count: 1)
    described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, room_count: room_count).call
  end

  describe "validation" do
    it "raises when end_date before start_date" do
      expect {
        described_class.new(hotel: hotel, start_date: today, end_date: today - 1).call
      }.to raise_error(ArgumentError, /end_date before start_date/)
    end

    it "raises when window > 180 days" do
      expect {
        described_class.new(hotel: hotel, start_date: today, end_date: today + 181).call
      }.to raise_error(ArgumentError, /window too large/)
    end
  end

  describe "#call" do
    it "returns correct day count" do
      7.times { |i| seed_day(today + i) }
      result = call(start_date: today, end_date: today + 6)
      expect(result[:days].length).to eq(7)
    end

    it "returns min_price and available: true for open days" do
      seed_day(today, price: 220.0, quantity: 3)
      day = call(start_date: today, end_date: today)[:days].first
      expect(day.min_price).to eq(220.0)
      expect(day.available).to be true
      expect(day.rooms_left).to eq(3)
    end

    it "returns available: false when quantity is 0" do
      RoomRate.create!(room_type: room_type, rate_plan: room_type.standard_rate_plan, date: today, price: 200, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: today, quantity: 0, status: "open")
      day = call(start_date: today, end_date: today)[:days].first
      expect(day.available).to be false
      expect(day.rooms_left).to eq(0)
    end

    it "returns available: false when inventory is closed" do
      seed_day(today, status: "closed")
      day = call(start_date: today, end_date: today)[:days].first
      expect(day.available).to be false
    end

    it "returns min_price across multiple room types" do
      room_type2 = RoomType.create!(hotel: hotel, name: "Suite", quantity: 2, max_adults: 2, base_price: 500, room_number_mode: "range")
      RoomRate.create!(room_type: room_type, rate_plan: room_type.standard_rate_plan, date: today, price: 300, currency: "MYR")
      RoomRate.create!(room_type: room_type2, rate_plan: room_type2.standard_rate_plan, date: today, price: 150, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: today, quantity: 5, status: "open")
      RoomInventory.create!(room_type: room_type2, date: today, quantity: 2, status: "open")
      day = call(start_date: today, end_date: today)[:days].first
      expect(day.min_price).to eq(150.0)
    end

    it "shows price of available room type when cheaper one is sold out" do
      room_type2 = RoomType.create!(hotel: hotel, name: "Suite", quantity: 2, max_adults: 2, base_price: 500, room_number_mode: "range")
      RoomRate.create!(room_type: room_type, rate_plan: room_type.standard_rate_plan, date: today, price: 150, currency: "MYR")
      RoomRate.create!(room_type: room_type2, rate_plan: room_type2.standard_rate_plan, date: today, price: 300, currency: "MYR")
      RoomInventory.create!(room_type: room_type,  date: today, quantity: 0, status: "open") # sold out
      RoomInventory.create!(room_type: room_type2, date: today, quantity: 2, status: "open")
      day = call(start_date: today, end_date: today)[:days].first
      expect(day.min_price).to eq(300.0)  # not 150 — that room is sold out
      expect(day.available).to be true
    end

    it "excludes nights where inventory < room_count" do
      RoomRate.create!(room_type: room_type, rate_plan: room_type.standard_rate_plan, date: today, price: 200, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: today, quantity: 2, status: "open")
      day = call(start_date: today, end_date: today, room_count: 3)[:days].first
      expect(day.available).to be false
      expect(day.rooms_left).to eq(0)
    end

    it "returns nil min_price for days with no rate" do
      day = call(start_date: today, end_date: today)[:days].first
      expect(day.min_price).to be_nil
      expect(day.available).to be false
    end

    it "uses the active Standard plan's category price when inventory exists without a daily row" do
      RoomInventory.create!(room_type: room_type, date: today, quantity: 3, status: "open")

      day = call(start_date: today, end_date: today)[:days].first

      expect(day.min_price).to eq(100.0)
      expect(day.available).to be true
    end

    it "does not fall back to an archived Standard plan" do
      room_type.standard_rate_plan.archive!
      RoomInventory.create!(room_type: room_type, date: today, quantity: 3, status: "open")

      day = call(start_date: today, end_date: today)[:days].first

      expect(day.min_price).to be_nil
      expect(day.available).to be false
    end

    it "returns currency from room rates" do
      seed_day(today)
      result = call(start_date: today, end_date: today)
      expect(result[:currency]).to eq("MYR")
    end
  end
end
