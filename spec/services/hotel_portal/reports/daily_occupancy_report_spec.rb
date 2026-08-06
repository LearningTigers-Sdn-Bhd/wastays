# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyOccupancyReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  describe "#call" do
    it "computes daily and total occupancy metrics for selected hotel and range" do
      room_type = create(:room_type, hotel: hotel, quantity: 10)
      create(:room_inventory, room_type: room_type, date: start_date, quantity: 8, status: "open")
      create(:room_inventory, room_type: room_type, date: end_date, quantity: 10, status: "open")

      group = create(:group_booking, hotel: hotel)
      first_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 1, status: "confirmed", check_in: start_date, check_out: end_date + 1.day, total_amount: 200)
      second_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "confirmed", check_in: start_date, check_out: end_date + 1.day, total_amount: 200)
      create(:booking_room, booking: first_booking, room_type: room_type, subtotal: 150)
      create(:booking_room, booking: second_booking, room_type: room_type, subtotal: 150)

      create(:booking, hotel: other_hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day, total_amount: 500)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(2)
      expect(result.rows[0][:rooms_sold]).to eq(2)
      expect(result.rows[0][:rooms_available]).to eq(8)
      expect(result.rows[0][:room_revenue]).to eq(150.to_d)
      expect(result.rows[1][:rooms_sold]).to eq(2)
      expect(result.rows[1][:rooms_available]).to eq(10)

      expect(result.totals[:rooms_sold]).to eq(4)
      expect(result.totals[:rooms_available]).to eq(18)
      expect(result.totals[:room_revenue]).to eq(300.to_d)
      expect(result.totals[:occupancy_rate]).to eq(4.to_d / 18)
      expect(result.totals[:adr]).to eq(75.to_d)
      expect(result.totals[:revpar]).to eq(300.to_d / 18)
    end

    it "uses room_type quantity fallback when room_inventory is missing" do
      create(:room_type, hotel: hotel, quantity: 6)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: start_date).call

      expect(result.rows.first[:rooms_available]).to eq(6)
    end

    it "treats closed inventory as zero availability" do
      room_type = create(:room_type, hotel: hotel, quantity: 6)
      create(:room_inventory, room_type: room_type, date: start_date, quantity: 6, status: "closed")

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: start_date).call

      expect(result.rows.first[:rooms_available]).to eq(0)
      expect(result.rows.first[:occupancy_rate]).to eq(0.to_d)
      expect(result.rows.first[:revpar]).to eq(0.to_d)
    end

    it "falls back to booking total_amount when booking_room subtotal is zero" do
      room_type = create(:room_type, hotel: hotel, quantity: 5)
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date, check_out: start_date + 2.days, total_amount: 240)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 0)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: start_date).call

      expect(result.rows.first[:room_revenue]).to eq(120.to_d)
      expect(result.rows.first[:adr]).to eq(120.to_d)
    end

    it "adds posted tax to room revenue for total revenue" do
      room_type = create(:room_type, hotel: hotel, quantity: 5)
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date, check_out: start_date + 1.day, total_amount: 100)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 100)
      booking_folio = create(:booking_folio, booking: booking)
      create(:folio_transaction, booking_folio: booking_folio, category: "tax", posting_date: start_date, amount: 6)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: start_date).call

      expect(result.rows.first[:tax_amount]).to eq(6.to_d)
      expect(result.rows.first[:total_revenue]).to eq(106.to_d)
      expect(result.totals[:tax_amount]).to eq(6.to_d)
      expect(result.totals[:total_revenue]).to eq(106.to_d)
    end
  end
end
