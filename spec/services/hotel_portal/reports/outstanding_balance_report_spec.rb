# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::OutstandingBalanceReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 7) }
  let(:end_date) { Date.new(2026, 5, 8) }

  describe "#call" do
    it "includes only non-captured bookings in configured statuses for selected hotel and range" do
      room_type = create(:room_type, hotel: hotel, name: "Executive King")

      included = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, total_amount: 220, guest_name: "Outstanding Guest")
      create(:booking_room, booking: included, room_type: room_type, quantity: 1, subtotal: 220, room_number: "101")

      create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", check_in: start_date, check_out: start_date + 1.day, total_amount: 300, guest_name: "Captured Guest")
      create(:booking, hotel: hotel, status: "cancelled", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, total_amount: 150, guest_name: "Cancelled Guest")
      create(:booking, hotel: other_hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, total_amount: 500, guest_name: "Other Hotel Guest")

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(1)
      expect(result.rows.first[:booking_id]).to eq(included.id)
      expect(result.totals[:booking_count]).to eq(1)
      expect(result.totals[:outstanding_amount]).to eq(220.to_d)
    end

    it "uses room snapshot/name fallback and room number fallback" do
      booking = create(:booking, hotel: hotel, status: "checked_in", payment_status: "authorized", check_in: start_date, check_out: start_date + 1.day)
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      create(:booking_room, booking: booking, room_type: room_type, quantity: 2, room_number: nil, room_type_snapshot: { "name" => "Snapshot Twin" })

      row = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call.rows.first

      expect(row[:room_details]).to eq("2x Snapshot Twin")
      expect(row[:room_numbers]).to eq("TBA")
    end
  end
end
