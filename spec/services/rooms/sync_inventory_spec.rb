# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::SyncInventory, type: :service do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101", "102" ], quantity: 2) }
  let(:start_date) { Date.current }
  let(:end_date) { Date.current }

  subject { described_class.new(hotel: hotel, room_type: room_type, start_date: start_date, end_date: end_date) }

  it "calculates correct inventory based on blocks and bookings" do
    # 1. Create one block
    create(:room_block, hotel: hotel, room_type: room_type, room_number: "101", start_date: start_date, end_date: end_date)

    # 2. Create one booking for the other room
    booking = create(:booking, hotel: hotel, check_in: start_date, check_out: start_date + 1.day, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "102", quantity: 1)

    subject.call

    inventory = RoomInventory.find_by(room_type: room_type, date: start_date)
    # 2 Total - 1 Block - 1 Booking = 0 remaining
    expect(inventory.quantity).to eq(0)
    expect(inventory.available_room_numbers).to eq([ "102" ])
  end
end
