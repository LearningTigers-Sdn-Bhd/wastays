# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::NonNationalReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 7, 1) }
  let(:end_date) { Date.new(2026, 7, 1) }

  describe "#call" do
    it "returns only in-house non-malaysian bookings for the selected date range" do
      included = create(
        :booking,
        hotel: hotel,
        status: "checked_in",
        check_in: start_date - 1.day,
        check_out: end_date + 1.day,
        checked_in_at: Time.zone.local(2026, 6, 30, 15, 45, 0),
        guest_name: "Kenji Sato",
        guest_country: "Japan",
        guest_home_address: "1 Chome-1-2 Oshiage, Sumida City, Tokyo, Japan",
        confirmation_token: "WS-FOREIGN"
      )
      create(:booking_room, booking: included, room_number: "305")
      guest = create(:guest, date_of_birth: Date.new(1985, 3, 15))
      create(:booking_guest, booking: included, guest: guest, is_primary: true)

      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Local Guest", guest_country: "Malaysia")
      create(:booking, hotel: hotel, status: "completed", check_in: start_date - 1.day, check_out: end_date, guest_name: "Checked Out Foreigner", guest_country: "Singapore")
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: end_date + 1.day, guest_name: "Not Checked In", guest_country: "Thailand")
      create(:booking, hotel: other_hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Other Hotel Guest", guest_country: "Indonesia")

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.start_date).to eq(start_date)
      expect(result.end_date).to eq(end_date)
      expect(result.totals[:guest_count]).to eq(1)
      expect(result.totals[:nights]).to eq(2)
      expect(result.rows.map { |row| row[:booking_id] }).to eq([ included.id ])
      expect(result.rows.first[:guest_country]).to eq("Japan")
      expect(result.rows.first[:guest_home_address]).to eq("1 Chome-1-2 Oshiage, Sumida City, Tokyo, Japan\nKuala Lumpur\nJapan")
      expect(result.rows.first[:date_of_birth]).to eq(Date.new(1985, 3, 15))
      expect(result.rows.first[:checked_in_at]).to eq(Time.zone.local(2026, 6, 30, 15, 45, 0))
      expect(result.rows.first[:room_numbers]).to eq("305")
    end

    it "treats malaysia case-insensitively and supports checkout_required" do
      create(:booking, hotel: hotel, status: "checkout_required", check_in: start_date - 2.days, check_out: end_date, guest_name: "Due Out Foreigner", guest_country: "Singapore")
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Still Local", guest_country: "mALAySia")

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.totals[:guest_count]).to eq(1)
      expect(result.rows.map { |row| row[:guest_name] }).to eq([ "Due Out Foreigner" ])
    end
  end
end
