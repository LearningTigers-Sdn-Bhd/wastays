require "rails_helper"

RSpec.describe HotelOps::ApplyPricingRules do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:start_date) { Date.new(2026, 4, 20) } # Monday
  let(:end_date) { Date.new(2026, 4, 26) }   # Sunday

  subject(:service) { described_class.new(hotel: hotel, room_type_ids: [ room_type.id ], start_date: start_date, end_date: end_date, user: user) }

  describe "#call" do
    before do
      hotel.pricing_rules.create!(rule_type: "general", name: "General", price: 100, start_date: start_date, end_date: end_date)
      hotel.pricing_rules.create!(rule_type: "weekends", name: "Weekends", price: 150, start_date: start_date, end_date: end_date, weekdays: [ 5, 6, 0 ])
      hotel.pricing_rules.create!(rule_type: "school_holiday", name: "School Holiday", price: 220, start_date: Date.new(2026, 4, 24), end_date: Date.new(2026, 4, 25))
      hotel.pricing_rules.create!(rule_type: "public_holiday", name: "Kaamatan", price: 260, start_date: Date.new(2026, 4, 25), end_date: Date.new(2026, 4, 25))
    end

    it "creates daily rate records for selected room types" do
      expect {
        result = service.call
        expect(result[:success]).to eq(true)
      }.to change(RoomRate, :count).by(7)
    end

    it "uses highest price rule and tier tie-breaker" do
      service.call

      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 23)).price.to_f).to eq(100.0) # GP
      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 24)).price.to_f).to eq(220.0) # SC beats WK
      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 25)).price.to_f).to eq(260.0) # PH beats SC
    end

    it "supports custom weekend-day definitions" do
      hotel.pricing_rules.delete_all
      hotel.pricing_rules.create!(rule_type: "general", name: "General", price: 100, start_date: start_date, end_date: end_date)
      hotel.pricing_rules.create!(rule_type: "weekends", name: "Weekends", price: 170, start_date: start_date, end_date: end_date, weekdays: [ 4 ])
      custom_service = described_class.new(hotel: hotel, room_type_ids: [ room_type.id ], start_date: start_date, end_date: end_date, user: user)

      custom_service.call

      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 23)).price.to_f).to eq(170.0) # Thu
      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 26)).price.to_f).to eq(100.0) # Sun
    end

    it "supports one-day public holiday by leaving end date blank" do
      hotel.pricing_rules.delete_all
      hotel.pricing_rules.create!(rule_type: "general", name: "General", price: 100, start_date: start_date, end_date: end_date)
      hotel.pricing_rules.create!(rule_type: "public_holiday", name: "Labor Day", price: 300, start_date: Date.new(2026, 4, 23), end_date: Date.new(2026, 4, 23))
      one_day_service = described_class.new(hotel: hotel, room_type_ids: [ room_type.id ], start_date: start_date, end_date: end_date, user: user)

      one_day_service.call

      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 23)).price.to_f).to eq(300.0)
      expect(room_type.room_rates.find_by(date: Date.new(2026, 4, 24)).price.to_f).to eq(100.0)
    end

    it "removes stale room rates when no rule applies anymore" do
      create(:room_rate, room_type: room_type, date: Date.new(2026, 4, 23), price: 180)
      hotel.pricing_rules.delete_all

      expect {
        service.call
      }.to change(RoomRate, :count).by(-1)
    end
  end
end
