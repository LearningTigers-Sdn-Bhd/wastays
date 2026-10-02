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
    it "returns a 7-day occupancy snapshot" do
      room_type = create(:room_type, hotel: hotel)
      # The quantity is on the inventory record itself
      create(:room_inventory, room_type: room_type, date: Date.current, quantity: 10, status: "open")

      # Booking for today
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.tomorrow)
      snapshot = stats.occupancy_snapshot
      expect(snapshot.length).to eq(7)
      expect(snapshot.first[:date]).to eq(Date.current)
      expect(snapshot.first[:total]).to eq(10)
      expect(snapshot.first[:sold]).to eq(1)
      expect(snapshot.first[:percent]).to eq(10)
    end
  end
end
