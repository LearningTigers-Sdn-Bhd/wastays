# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::DashboardStats, type: :service do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:stats) { described_class.new(hotel) }

  describe "#bookings_this_month_count" do
    it "returns the count of active bookings created this month" do
      create(:booking, hotel: hotel, status: "confirmed", created_at: Time.current)
      create(:booking, hotel: hotel, status: "pending", created_at: Time.current) # Not active
      create(:booking, hotel: hotel, status: "confirmed", created_at: 2.months.ago)

      expect(stats.bookings_this_month_count).to eq(1)
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
