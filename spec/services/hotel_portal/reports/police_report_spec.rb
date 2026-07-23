# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::PoliceReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 7, 21) }
  let(:end_date) { start_date }

  describe "#call" do
    it "includes every reportable stay that overlaps the selected period" do
      prior_arrival = create(:booking, hotel:, status: "checked_in", check_in: start_date - 2.days, check_out: start_date + 2.days, guest_name: "Prior arrival")
      same_day_departure = create(:booking, hotel:, status: "completed", check_in: start_date - 2.days, check_out: start_date, guest_name: "Same day departure")
      create(:booking, hotel:, status: "confirmed", check_in: start_date + 1.day, check_out: start_date + 2.days, guest_name: "Future stay")
      create(:booking, hotel:, status: "cancelled", check_in: start_date, check_out: start_date + 1.day, guest_name: "Cancelled stay")
      create(:booking, hotel: other_hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Other hotel")

      result = described_class.new(hotel:, start_date:, end_date:).call

      expect(result.rows.map { |row| row[:booking_id] }).to contain_exactly(prior_arrival.id, same_day_departure.id)
    end

    it "uses primary guest data and hotel-local timestamps in a report row" do
      room_type = create(:room_type, hotel:, name: "Garden Chalet")
      booking = create(
        :booking,
        hotel:,
        status: "checked_in",
        confirmation_token: "POLICE-123",
        check_in: start_date,
        check_out: start_date + 2.days,
        checked_in_at: Time.zone.local(2026, 7, 21, 14, 30),
        guest_home_address: "12 Jalan Example, Kuching",
        guest_phone: "+60123456789"
      )
      create(:booking_room, booking:, room_type:, room_number: "G01")
      primary_guest = create(:guest, name: "Aiko Tanaka", country: "Japan", gender: "female", document_type: "passport", government_id: "P1234567", date_of_birth: Date.new(1990, 4, 12))
      create(:booking_guest, booking:, guest: primary_guest, is_primary: true)

      row = described_class.new(hotel:, start_date:, end_date:).call.rows.first

      expect(row).to include(
        booking_id: booking.id,
        guest_name: "Aiko Tanaka",
        confirmation_token: "POLICE-123",
        room_number: "G01",
        nationality: "Japan",
        gender: "Female",
        date_of_birth: "12 Apr 1990",
        address: "12 Jalan Example, Kuching",
        contact: "+60123456789",
        scheduled_check_in: "21 Jul 2026",
        actual_check_in: "21 Jul 2026\n10:30 PM",
        scheduled_check_out: "23 Jul 2026",
        actual_check_out: "-",
        nights_stayed: 2,
        status: "Checked in"
      )
    end
  end
end
