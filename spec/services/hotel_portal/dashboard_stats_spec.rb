# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::DashboardStats, type: :service do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:stats) { described_class.new(hotel) }

  describe "#bookings_this_month_count" do
    it "returns the count of revenue-generating bookings whose stay starts this month" do
      create(:booking, hotel: hotel, status: "confirmed", check_in: Time.current, check_out: 1.day.from_now)
      create(:booking, hotel: hotel, status: "pending", check_in: Time.current, check_out: 1.day.from_now) # Not revenue-generating
      create(:booking, hotel: hotel, status: "cancelled", check_in: Time.current, check_out: 1.day.from_now) # Not revenue-generating
      create(:booking, hotel: hotel, status: "confirmed", check_in: 2.months.ago, check_out: 2.months.ago + 1.day)

      expect(stats.bookings_this_month_count).to eq(1)
    end

    # .active excludes "completed", so a guest who already checked out this
    # month used to vanish from the month's own count the moment they left.
    it "still counts a booking that has already checked out this month" do
      create(:booking, hotel: hotel, status: "completed", check_in: Time.current, check_out: 1.day.from_now)

      expect(stats.bookings_this_month_count).to eq(1)
    end

    # An imported property has every row created on the day of the import.
    it "goes by the stay dates, not by when the booking was entered" do
      create(:booking, hotel: hotel, status: "confirmed", created_at: Time.current,
                       check_in: 2.months.from_now, check_out: 2.months.from_now + 1.day)

      expect(stats.bookings_this_month_count).to eq(0)
    end
  end

  describe "#revenue_this_month" do
    it "still counts a booking that has already checked out this month" do
      create(:booking, hotel: hotel, status: "completed", check_in: Time.current, check_out: 1.day.from_now, total_amount: 500)
      create(:booking, hotel: hotel, status: "cancelled", check_in: Time.current, check_out: 1.day.from_now, total_amount: 999)

      expect(stats.revenue_this_month).to eq(500)
    end

    it "leaves out a stay that starts in a later month, however recently it was entered" do
      create(:booking, hotel: hotel, status: "confirmed", created_at: Time.current,
                       check_in: 2.months.from_now, check_out: 2.months.from_now + 1.day, total_amount: 800)

      expect(stats.revenue_this_month).to eq(0)
    end
  end

  describe "#live_inventory" do
    # Bookings::InventoryManager decrements room_inventories.quantity by one
    # for every booking taken, so the record is already net of every sale --
    # subtracting the day's sold count from it again double-counted each sale.
    # A quiet room type (nothing sold) hid this completely, which is exactly
    # why it went unnoticed: remaining + sold only stopped adding up to total
    # once something actually sold that day.
    it "adds remaining and sold back up to total once something has sold today" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 8, status: "open")
      2.times do
        booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.tomorrow)
        create(:booking_room, booking: booking, room_type: room_type)
      end

      row = stats.live_inventory.find { |candidate| candidate[:room_type] == room_type }

      expect(row).to include(total: 10, sold: 2, remaining: 8)
      expect(row[:remaining] + row[:sold]).to eq(row[:total])
    end
  end

  describe "#occupancy_snapshot" do
    # room_inventories.quantity is what is left to sell, already net of every
    # booking (see #live_inventory), so dividing sales by it ran past 100%
    # the moment anything sold.
    it "measures rooms sold against the hotel's physical rooms" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 8, status: "open")
      2.times do
        booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.tomorrow)
        create(:booking_room, booking: booking, room_type: room_type)
      end

      snapshot = stats.occupancy_snapshot

      expect(snapshot.length).to eq(7)
      expect(snapshot.first).to include(date: Date.current, total: 10, sold: 2, percent: 20)
    end

    # 02:00 in Kuala Lumpur is still the previous day in UTC.
    it "starts on the hotel's today and counts the nights it is booked for" do
      hotel.update!(time_zone: "Kuala Lumpur")
      zone = hotel.hotel_time_zone
      room_type = create(:room_type, hotel: hotel, quantity: 10)

      travel_to zone.local(2026, 10, 9, 2, 0) do
        booking = create(:booking, hotel: hotel, status: "confirmed",
                                   check_in: zone.local(2026, 10, 9, 14), check_out: zone.local(2026, 10, 10, 12))
        create(:booking_room, booking: booking, room_type: room_type)

        snapshot = stats.occupancy_snapshot

        expect(snapshot.first).to include(date: Date.new(2026, 10, 9), sold: 1)
        expect(snapshot.second).to include(date: Date.new(2026, 10, 10), sold: 0)
      end
    end
  end
end
