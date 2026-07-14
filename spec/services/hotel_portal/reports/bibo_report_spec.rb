# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::BiboReport, type: :service do
  let(:hotel) { create(:hotel, time_zone: "UTC") }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 7) }
  let(:end_date) { Date.new(2026, 5, 7) }
  let(:service) { described_class.new(hotel: hotel, start_date: start_date, end_date: end_date) }

  describe "#call" do
    it "returns boat ins and outs for the selected hotel and date range" do
      booking1 = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 2.days)
      guest1 = create(:guest, name: "John Doe")
      booking_guest1 = create(:booking_guest, booking: booking1, guest: guest1, is_primary: true, boat_in_at: start_date.beginning_of_day + 10.hours)

      booking2 = create(:booking, hotel: hotel, check_in: start_date - 2.days, check_out: start_date)
      guest2 = create(:guest, name: "Jane Smith")
      booking_guest2 = create(:booking_guest, booking: booking2, guest: guest2, is_primary: true, boat_out_at: start_date.beginning_of_day + 15.hours)

      # Booking at another hotel
      other_booking = create(:booking, hotel: other_hotel, check_in: start_date, check_out: start_date + 1.day)
      create(:booking_guest, booking: other_booking, guest: guest1, is_primary: true, boat_in_at: start_date.beginning_of_day + 10.hours)

      result = service.call

      expect(result.start_date).to eq(start_date)
      expect(result.end_date).to eq(end_date)
      expect(result.boat_in_count).to eq(1)
      expect(result.boat_out_count).to eq(1)

      expect(result.boat_ins.first[:guest_name]).to eq("John Doe")
      expect(result.boat_outs.first[:guest_name]).to eq("Jane Smith")
    end

    it "formats boat times in the hotel timezone" do
      hotel.update!(time_zone: "Asia/Kuala_Lumpur")
      booking = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 2.days)
      guest = create(:guest, name: "John Doe")
      # 10:00 UTC is 18:00 (6:00 PM) in Asia/Kuala_Lumpur
      create(:booking_guest, booking: booking, guest: guest, is_primary: true, boat_in_at: Time.utc(2026, 5, 7, 10, 0))

      result = service.call
      expect(result.boat_ins.first[:boat_time]).to eq("06:00 PM")
    end
  end
end
