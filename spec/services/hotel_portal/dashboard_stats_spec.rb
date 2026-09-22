# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::DashboardStats, type: :service do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:stats) { described_class.new(hotel) }

  describe "#bookings_this_month_count" do
    it "returns the count of revenue-generating bookings created this month" do
      create(:booking, hotel: hotel, status: "confirmed", created_at: Time.current)
      create(:booking, hotel: hotel, status: "pending", created_at: Time.current) # Not revenue-generating
      create(:booking, hotel: hotel, status: "cancelled", created_at: Time.current) # Not revenue-generating
      create(:booking, hotel: hotel, status: "confirmed", created_at: 2.months.ago)

      expect(stats.bookings_this_month_count).to eq(1)
    end

    # .active excludes "completed", so a guest who already checked out this
    # month used to vanish from the month's own count the moment they left.
    it "still counts a booking that has already checked out this month" do
      create(:booking, hotel: hotel, status: "completed", created_at: Time.current)

      expect(stats.bookings_this_month_count).to eq(1)
    end
  end

  describe "#revenue_this_month" do
    it "still counts a booking that has already checked out this month" do
      create(:booking, hotel: hotel, status: "completed", created_at: Time.current, total_amount: 500)
      create(:booking, hotel: hotel, status: "cancelled", created_at: Time.current, total_amount: 999)

      expect(stats.revenue_this_month).to eq(500)
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
