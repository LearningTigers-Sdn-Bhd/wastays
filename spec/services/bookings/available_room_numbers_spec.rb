# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::AvailableRoomNumbers do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101", "102", "103" ]) }
  let(:check_in) { Date.current }
  let(:check_out) { Date.current + 1.day }

  subject { described_class.new(hotel: hotel, room_type: room_type, check_in: check_in, check_out: check_out) }

  it "returns all room numbers when no bookings exist" do
    expect(subject.call).to match_array([ "101", "102", "103" ])
  end

  it "excludes room numbers already occupied" do
    create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed", hotel_snapshot: { room_number: "101" })
    expect(subject.call).to match_array([ "102", "103" ])
  end

  it "includes room numbers of excluded booking id (for editing)" do
    booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed", hotel_snapshot: { room_number: "101" })
    service = described_class.new(hotel: hotel, room_type: room_type, check_in: check_in, check_out: check_out, exclude_booking_id: booking.id)
    expect(service.call).to match_array([ "101", "102", "103" ])
  end
end
