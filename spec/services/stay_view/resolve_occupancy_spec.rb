# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ResolveOccupancy do
  let(:booking) do
    StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 17)
    )
  end

  it "projects arrival and departure events using checkout-exclusive occupancy" do
    arrival = described_class.call(date: Date.new(2026, 7, 16), bookings: [ booking ])
    departure = described_class.call(date: Date.new(2026, 7, 17), bookings: [ booking ])
    after_departure = described_class.call(date: Date.new(2026, 7, 18), bookings: [ booking ])

    expect(arrival.map(&:state)).to eq([ :arrival ])
    expect(departure.map(&:state)).to eq([ :departure ])
    expect(after_departure.map(&:state)).to eq([ :available ])
  end

  it "supports a departure and another arrival in the same room on one date" do
    arriving = booking.with(
      booking_room_id: 12,
      booking_id: 8,
      check_in: Date.new(2026, 7, 17),
      check_out: Date.new(2026, 7, 19)
    )

    occupancies = described_class.call(date: Date.new(2026, 7, 17), bookings: [ booking, arriving ])

    expect(occupancies.map(&:state)).to contain_exactly(:departure, :arrival)
    expect(occupancies).to be_frozen
  end
end
