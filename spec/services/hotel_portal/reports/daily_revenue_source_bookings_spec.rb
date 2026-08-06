# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueSourceBookings do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 6) }
  let(:end_date) { Date.new(2026, 5, 7) }

  it "returns bookings whose folio activity matches the normalized source within the date range" do
    walk_in_booking = create(:booking, hotel: hotel, source: "walk_in", guest_name: "Walk-in Guest", confirmation_token: "WS-WALK")
    walk_in_folio = create(:booking_folio, booking: walk_in_booking, hotel: hotel)
    create(:folio_transaction, booking_folio: walk_in_folio, category: "accommodation", amount: 100, posting_date: start_date)

    agoda_booking = create(:booking, hotel: hotel, source: "agoda", guest_name: "Agoda Guest")
    agoda_folio = create(:booking_folio, booking: agoda_booking, hotel: hotel)
    create(:folio_transaction, booking_folio: agoda_folio, category: "accommodation", amount: 100, posting_date: start_date)

    outside_range_booking = create(:booking, hotel: hotel, source: "walk_in", guest_name: "Outside Range Guest")
    outside_range_folio = create(:booking_folio, booking: outside_range_booking, hotel: hotel)
    create(:folio_transaction, booking_folio: outside_range_folio, category: "accommodation", amount: 100, posting_date: start_date - 10.days)

    detail = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, source: "Walk-in").call

    expect(detail.entries.map(&:confirmation_token)).to eq([ "WS-WALK" ])
    expect(detail.entries.first.guest_name).to eq("Walk-in Guest")
  end

  it "excludes bookings from another hotel" do
    other_hotel = create(:hotel)
    booking = create(:booking, hotel: other_hotel, source: "walk_in")
    folio = create(:booking_folio, booking: booking, hotel: other_hotel)
    create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100, posting_date: start_date)

    detail = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, source: "Walk-in").call

    expect(detail.entries).to be_empty
  end
end
