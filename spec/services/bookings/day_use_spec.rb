# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Day-use stays" do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 2, room_numbers: [ "101", "102" ]) }
  let(:day_use_plan) { create(:rate_plan, :custom, name: "Day Use 6h", day_use_hours: 6, room_type: room_type) }
  let(:today) { Date.current }
  let(:arrival) { hotel.hotel_time_zone.parse("#{today} 09:00") }
  let(:params) do
    {
      guest_name: "Day Guest", guest_email: "day@example.com", guest_phone: "123456",
      check_in: arrival, check_out: arrival + 1.hour,
      room_type_id: room_type.id, room_number: "101", rate_plan_id: day_use_plan.id, adults: 2
    }
  end

  before do
    dispatcher = instance_double(Notifications::Dispatcher, call: [])
    allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)
    create(:room_rate, room_type: room_type, rate_plan: day_use_plan, date: today, price: 90)
  end

  describe RatePlan do
    it "is sold to staff only" do
      expect(day_use_plan.bookable_by?(:staff)).to be true
      expect(day_use_plan.bookable_by?(:public)).to be false
      expect(day_use_plan.bookable_by?(:corporate)).to be false
    end

    it "is not available on a per-person hotel" do
      per_person_plan = build(:rate_plan, :custom, hotel: create(:hotel, :per_person), day_use_hours: 6)

      expect(per_person_plan).not_to be_valid
      expect(per_person_plan.errors[:day_use_hours]).to include("is only available when the hotel sells per room")
    end

    it "rejects hours outside a single day" do
      expect(build(:rate_plan, :custom, day_use_hours: 0)).not_to be_valid
      expect(build(:rate_plan, :custom, day_use_hours: 25)).not_to be_valid
    end

    it "is not distributed to channels" do
      expect(ChannelManagers::ChannexRatePlanCapability.call(rate_plan: day_use_plan)).to be_unsupported
    end
  end

  describe Bookings::RateOptions do
    def options(check_in, check_out)
      described_class.new(room_type: room_type, check_in: check_in, check_out: check_out).call
    end

    it "offers only day-use plans for a same-day request, at the fixed price" do
      result = options(today, today)

      expect(result.pluck(:id)).to eq([ day_use_plan.id ])
      expect(result.first[:total_amount]).to eq("90.0")
    end

    it "keeps day-use plans out of an overnight request" do
      expect(options(today, today + 1.day).pluck(:id)).not_to include(day_use_plan.id)
    end
  end

  describe Bookings::CreateManualBooking do
    it "ends the stay at arrival plus the plan's hours and charges the fixed price" do
      result = described_class.new(hotel: hotel, params: params).call

      expect(result.success?).to be true
      booking = result.booking
      expect(booking.check_out).to eq(arrival + 6.hours)
      expect(booking).to be_day_use
      expect(booking.day_use_hours).to eq(6)
      expect(booking.total_amount).to eq(90.to_d)
    end

    it "does not take a night out of the room category's inventory" do
      described_class.new(hotel: hotel, params: params).call

      expect(room_type.room_inventories.where(date: today)).to all(have_attributes(quantity: room_type.quantity))
    end

    it "rejects a block that would run past midnight" do
      late = hotel.hotel_time_zone.parse("#{today} 20:00")
      result = described_class.new(hotel: hotel, params: params.merge(check_in: late, check_out: late + 1.hour)).call

      expect(result.success?).to be false
      expect(result.errors.to_sentence).to include("before midnight")
    end

    it "refuses a day-use plan for a multi-night stay" do
      result = described_class.new(hotel: hotel, params: params.merge(check_out: arrival + 1.day)).call

      expect(result.success?).to be false
    end

    it "refuses the same room for an overlapping day-use block" do
      described_class.new(hotel: hotel, params: params).call
      second = described_class.new(hotel: hotel, params: params.merge(check_in: arrival + 2.hours, check_out: arrival + 3.hours)).call

      expect(second.success?).to be false
    end

    it "lets the room turn over for a back-to-back day-use block" do
      described_class.new(hotel: hotel, params: params).call
      later = arrival + 6.hours
      second = described_class.new(hotel: hotel, params: params.merge(check_in: later, check_out: later + 1.hour)).call

      expect(second.success?).to be true
    end
  end

  describe Bookings::ScheduledStay do
    it "bills one date for a same-day stay and none for a backwards one" do
      expect(described_class.stay_dates(hotel: hotel, check_in: arrival, check_out: arrival + 6.hours)).to eq([ today ])
      expect(described_class.stay_dates(hotel: hotel, check_in: arrival, check_out: arrival - 1.hour)).to eq([])
      expect(described_class.stay_dates(hotel: hotel, check_in: arrival, check_out: arrival + 1.day)).to eq([ today ])
    end
  end
end
