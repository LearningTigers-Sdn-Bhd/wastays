# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::StatusResolver do
  it "returns occupied when a checked-in booking overlaps today" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    booking = create(:booking, hotel: hotel, status: "checked_in", check_in: Date.current, check_out: Date.tomorrow, checked_in_at: Time.current)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", quantity: 1, subtotal: 200)
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    result = described_class.new(hotel: hotel, room_type: room_type, room_number: "101", date: Date.current).call

    expect(result.status).to eq("occupied")
    expect(result.assignable).to be(false)
  end

  it "returns persisted readiness status when the room is not occupied" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

    result = described_class.new(hotel: hotel, room_type: room_type, room_number: "101", date: Date.current).call

    expect(result.status).to eq("pending_cleaning")
    expect(result.assignable).to be(false)
  end
end
