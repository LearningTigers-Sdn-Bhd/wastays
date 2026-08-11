# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::AllocateGroupSnapshot do
  it "orders active bookings and prefers matching room and rate plan pairs" do
    room_type = double(id: 10)
    rate_plan = double(id: 20)
    fallback_room = double(room_type_id: 99, rate_plan_id: 99)
    matching_room = double(room_type_id: room_type.id, rate_plan_id: rate_plan.id)
    fallback_rooms = double(first: fallback_room, first!: fallback_room)
    matching_rooms = double(first: matching_room, first!: matching_room)
    fallback = double(id: 1, status: "confirmed", group_position: 1, booking_rooms: fallback_rooms)
    matching = double(id: 2, status: "confirmed", group_position: 2, booking_rooms: matching_rooms)
    cancelled = double(id: 3, status: "cancelled", group_position: 0, booking_rooms: matching_rooms)

    allocations = described_class.call(
      bookings: [ matching, cancelled, fallback ],
      rooms: [ { room_type:, rate_plan:, quantity: 1 }, { room_type: nil, rate_plan: nil, quantity: 0 } ]
    )

    expect(allocations.map { |allocation| allocation[:booking] }).to eq([ matching, fallback ])
    expect(allocations.map { |allocation| allocation.values_at(:room_index, :unit_index) }).to eq([ [ 0, 0 ], [ 1, 0 ] ])
    expect(allocations.first[:booking_room]).to eq(matching_room)
  end

  it "raises when room quantities exceed the available active bookings" do
    booking_room = double(room_type_id: 1, rate_plan_id: 1)
    rooms = double(first: booking_room, first!: booking_room)
    booking = double(id: 1, status: "confirmed", group_position: nil, booking_rooms: rooms)

    expect {
      described_class.call(bookings: [ booking ], rooms: [ { quantity: 2 } ])
    }.to raise_error(ArgumentError, "Financial room cannot be allocated to a booking")
  end
end
