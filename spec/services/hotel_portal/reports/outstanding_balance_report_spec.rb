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
      create(:booking_room, booking: included, room_type: room_type, subtotal: 220, room_number: "101")
      included_folio = create(:booking_folio, booking: included, hotel: hotel)
      create(:folio_transaction, booking_folio: included_folio, transaction_type: "charge", category: "accommodation", amount: 220)
      create(:folio_transaction, booking_folio: included_folio, transaction_type: "payment", category: "cash", amount: 40)

      captured = create(:booking, hotel: hotel, status: "confirmed", payment_status: "captured", check_in: start_date, check_out: start_date + 1.day, total_amount: 300, guest_name: "Captured Guest")
      captured_folio = create(:booking_folio, booking: captured, hotel: hotel)
      create(:folio_transaction, booking_folio: captured_folio, transaction_type: "charge", category: "accommodation", amount: 300)
      create(:folio_transaction, booking_folio: captured_folio, transaction_type: "payment", category: "cash", amount: 300)
      create(:booking, hotel: hotel, status: "cancelled", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, total_amount: 150, guest_name: "Cancelled Guest")
      other_booking = create(:booking, hotel: other_hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day, total_amount: 500, guest_name: "Other Hotel Guest")
      other_folio = create(:booking_folio, booking: other_booking, hotel: other_hotel)
      create(:folio_transaction, booking_folio: other_folio, transaction_type: "charge", category: "accommodation", amount: 500)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.size).to eq(1)
      expect(result.rows.first[:booking_id]).to eq(included.id)
      expect(result.totals[:booking_count]).to eq(1)
      expect(result.totals[:outstanding_amount]).to eq(180.to_d)
    end

    it "uses room snapshot/name fallback and room number fallback for grouped child bookings" do
      group = create(:group_booking, hotel: hotel)
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Twin")
      first_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 1, status: "checked_in", payment_status: "authorized", check_in: start_date, check_out: start_date + 1.day)
      second_booking = create(:booking, hotel: hotel, group_booking: group, group_position: 2, status: "checked_in", payment_status: "authorized", check_in: start_date, check_out: start_date + 1.day)
      create(:booking_room, booking: first_booking, room_type: room_type, room_number: nil, room_type_snapshot: { "name" => "Snapshot Twin" })
      create(:booking_room, booking: second_booking, room_type: room_type, room_number: nil, room_type_snapshot: {})
      first_folio = create(:booking_folio, booking: first_booking, hotel: hotel)
      second_folio = create(:booking_folio, booking: second_booking, hotel: hotel)
      create(:folio_transaction, booking_folio: first_folio, transaction_type: "charge", category: "accommodation", amount: 50)
      create(:folio_transaction, booking_folio: second_folio, transaction_type: "charge", category: "accommodation", amount: 50)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows.map { |row| row[:booking_id] }).to contain_exactly(first_booking.id, second_booking.id)
      expect(result.rows.map { |row| row[:room_details] }).to contain_exactly("1x Snapshot Twin", "1x Deluxe Twin")
      expect(result.rows.map { |row| row[:room_numbers] }).to contain_exactly("TBA", "TBA")
      expect(result.totals[:booking_count]).to eq(2)
      expect(result.totals[:outstanding_amount]).to eq(100.to_d)
    end

    it "excludes pending bookings with a settled folio balance" do
      booking = create(:booking, hotel: hotel, status: "confirmed", payment_status: "pending", check_in: start_date, check_out: start_date + 1.day)
      folio = create(:booking_folio, booking: booking, hotel: hotel)
      create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
      create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 100)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.rows).to be_empty
      expect(result.totals[:outstanding_amount]).to eq(0.to_d)
    end
  end
end
