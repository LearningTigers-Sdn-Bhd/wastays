# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::RoomStatusBoardBuilder do
  it "builds date headers, room rows, statuses, and booking blocks" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel, name: "Deluxe", room_numbers: [ "101" ], quantity: 1, smoking_allowed: true, pets_allowed: true)
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current, check_out: Date.current + 2.days, guest_name: "Sarah Jenkins")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 200)

    room_status_board_data = described_class.new(hotel: hotel, start_date: Date.current, days: 7).call

    expect(room_status_board_data[:dates].size).to eq(7)
    expect(room_status_board_data[:room_groups].first[:room_type]).to eq(room_type)
    row = room_status_board_data[:room_groups].first[:rooms].first
    expect(row[:room_number]).to eq("101")
    expect(row[:status][:status]).to eq("ready")
    expect(row[:room_type].smoking_allowed).to be(true)
    expect(row[:room_type].pets_allowed).to be(true)
    expect(row[:blocks].first[:guest_name]).to eq("Sarah Jenkins")
  end
end
