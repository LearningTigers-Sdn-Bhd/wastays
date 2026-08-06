# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boats::Schedule do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur", allow_boat_information: true) }

  subject(:schedule) { described_class.new(hotel) }

  def slot(kind, time, **meals)
    create(:hotel_boat_schedule, hotel: hotel, kind: kind, time: time, **meals)
  end

  describe "#in_choices" do
    it "sorts the timetable and leads with the none option" do
      slot("boat_in", "11:00")
      slot("boat_in", "08:00")

      expect(schedule.in_choices).to eq(
        [ [ "No boat transfer", "" ], [ "8:00 AM", "08:00" ], [ "11:00 AM", "11:00" ] ]
      )
    end

    it "omits retired slots" do
      slot("boat_in", "08:00")
      slot("boat_in", "09:30").archive!

      expect(schedule.in_choices.map(&:last)).to eq([ "", "08:00" ])
    end

    it "still offers a retired slot to the guest already booked on it" do
      slot("boat_in", "08:00")
      slot("boat_in", "09:30").archive!

      expect(schedule.in_choices(current: "09:30").map(&:last)).to eq([ "", "08:00", "09:30" ])
    end

    it "does not invent an option for a time that was never a slot" do
      slot("boat_in", "08:00")

      expect(schedule.in_choices(current: "06:15").map(&:last)).to eq([ "", "08:00" ])
    end
  end

  describe "slot times" do
    it "are wall-clock labels, read and written identically from any zone" do
      written = [ "UTC", "Hawaii", "Kuala Lumpur" ].map do |zone|
        Time.use_zone(zone) do
          record = create(:hotel_boat_schedule, hotel: create(:hotel), kind: "boat_in", time: "08:00")
          [ record.reload.time_of_day, Time.use_zone("Hawaii") { record.reload.time_of_day } ]
        end
      end

      expect(written.flatten.uniq).to eq([ "08:00" ])
    end
  end

  describe "#enabled?" do
    it "is false until the property has a live slot" do
      expect(schedule.enabled?).to be false

      live = slot("boat_in", "08:00")
      expect(described_class.new(hotel.reload).enabled?).to be true

      live.archive!
      expect(described_class.new(hotel.reload).enabled?).to be false
    end

    it "is false when the property has boat information switched off" do
      slot("boat_in", "08:00")
      hotel.update!(allow_boat_information: false)

      expect(described_class.new(hotel.reload).enabled?).to be false
    end
  end

  describe "#meals_for" do
    it "reads the entitlements stored on the slot" do
      slot("boat_in", "08:00", has_breakfast: true, has_lunch: true, has_dinner: false)
      timestamp = described_class.timestamp(hotel: hotel, date: Date.new(2026, 8, 1), time: "08:00")

      expect(schedule.meals_for(timestamp, "boat_in")).to eq(%i[breakfast lunch])
    end

    it "still resolves through a retired slot, so history never rewrites" do
      slot("boat_in", "08:00", has_breakfast: true).archive!
      timestamp = described_class.timestamp(hotel: hotel, date: Date.new(2026, 8, 1), time: "08:00")

      expect(described_class.new(hotel.reload).meals_for(timestamp, "boat_in")).to eq(%i[breakfast])
    end

    it "returns nothing for a time with no slot at all" do
      timestamp = described_class.timestamp(hotel: hotel, date: Date.new(2026, 8, 1), time: "06:15")

      expect(schedule.meals_for(timestamp, "boat_in")).to eq([])
    end
  end

  describe ".timestamp" do
    let(:check_in) { Time.utc(2026, 8, 1, 4, 0) }

    it "builds the time in the property's zone whatever zone the request runs in" do
      built = [ "UTC", "Hawaii", "Kuala Lumpur" ].map do |zone|
        Time.use_zone(zone) { described_class.timestamp(hotel: hotel, date: check_in, time: "08:00") }
      end

      expect(built.uniq.size).to eq(1)
      expect(built.first.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%d %H:%M")).to eq("2026-08-01 08:00")
    end

    it "reads the calendar day in the property's zone" do
      # 16:00 UTC is already the next day in Kuala Lumpur.
      timestamp = described_class.timestamp(hotel: hotel, date: Time.utc(2026, 8, 1, 16, 0), time: "08:00")

      expect(timestamp.in_time_zone(hotel.hotel_time_zone).to_date).to eq(Date.new(2026, 8, 2))
    end

    it "returns nil for a blank date or an unusable time" do
      expect(described_class.timestamp(hotel: hotel, date: nil, time: "08:00")).to be_nil
      expect(described_class.timestamp(hotel: hotel, date: check_in, time: "")).to be_nil
      expect(described_class.timestamp(hotel: hotel, date: check_in, time: "25:00")).to be_nil
    end
  end

  describe ".time_of_day" do
    it "round-trips a timestamp back to the slot it was picked from" do
      timestamp = described_class.timestamp(hotel: hotel, date: Time.utc(2026, 8, 1, 4, 0), time: "15:30")

      expect(described_class.time_of_day(hotel: hotel, timestamp: timestamp)).to eq("15:30")
    end

    it "returns nil when nothing is stored" do
      expect(described_class.time_of_day(hotel: hotel, timestamp: nil)).to be_nil
    end
  end
end
