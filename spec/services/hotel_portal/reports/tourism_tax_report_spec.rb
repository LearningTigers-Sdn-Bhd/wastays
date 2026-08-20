# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::TourismTaxReport, type: :service do
  let(:hotel) { create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10) }
  let(:other_hotel) { create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10) }
  let(:start_date) { Date.new(2026, 7, 1) }
  let(:end_date) { Date.new(2026, 7, 1) }

  describe "#call" do
    it "returns only in-house foreign guests with tax due and collected totals" do
      included = create(
        :booking,
        hotel: hotel,
        status: "checked_in",
        check_in: start_date - 2.days,
        check_out: end_date + 1.day,
        guest_name: "Kenji Sato",
        guest_country: "Japan",
        confirmation_token: "WS-TTX",
        tourism_tax_amount: 20,
        tourism_tax_collected: true
      )
      create(:booking_room, booking: included, room_number: "305")

      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Uncollected Guest", guest_country: "Singapore", tourism_tax_amount: 10, tourism_tax_collected: false)
      create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Local Guest", guest_country: "Malaysia", tourism_tax_amount: 10, tourism_tax_collected: true)
      create(:booking, hotel: hotel, status: "completed", check_in: start_date - 1.day, check_out: end_date, guest_name: "Checked Out Guest", guest_country: "Thailand", tourism_tax_amount: 10, tourism_tax_collected: true)
      create(:booking, hotel: other_hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "Other Hotel Guest", guest_country: "Indonesia", tourism_tax_amount: 10, tourism_tax_collected: true)

      result = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(result.totals[:guest_count]).to eq(2)
      expect(result.totals[:total_due]).to eq(30.to_d)
      expect(result.totals[:total_collected]).to eq(20.to_d)
      expect(result.rows.map { |row| row[:guest_name] }).to eq([ "Kenji Sato", "Uncollected Guest" ])
      expect(result.rows.first[:collection_status]).to eq("Collected")
      expect(result.rows.second[:collection_status]).to eq("Pending")
      expect(result.rows.first[:room_numbers]).to eq("305")
    end
  end
end
