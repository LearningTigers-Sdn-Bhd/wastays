# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoomIdentifiable do
  let(:hotel) { create(:hotel) }
  let!(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102]) }
  let(:room) { hotel.rooms.find_by!(number: "101") }

  it "links a room status to its physical room" do
    status = create(:room_status, hotel:, room_type:, room_number: "101")

    expect(status.room).to eq(room)
  end

  it "links a room block to its physical room" do
    block = create(:room_block, hotel:, room_type:, room_number: "101")

    expect(block.room).to eq(room)
  end

  it "links a booking room through its booking's hotel" do
    booking = create(:booking, hotel:)
    booking_room = create(:booking_room, booking:, room_type:, room_number: "101")

    expect(booking_room.room).to eq(room)
  end

  it "trims the number before it matches" do
    status = create(:room_status, hotel:, room_type:, room_number: " 101 ")

    expect(status.room).to eq(room)
  end

  it "leaves the reference empty when the hotel has no such room" do
    status = create(:room_status, hotel:, room_type:, room_number: "999")

    expect(status.room).to be_nil
    expect(status.room_number).to eq("999")
  end

  it "still names an archived room, because the identity outlives the listing" do
    renumber_room_type!(room_type, %w[102])

    expect(room.reload).to be_archived
    expect(create(:room_status, hotel:, room_type:, room_number: "101").room).to eq(room)
  end

  it "does not overwrite a reference the caller set" do
    other = hotel.rooms.find_by!(number: "102")
    status = create(:room_status, hotel:, room_type:, room_number: "101", room: other)

    expect(status.room).to eq(other)
  end

  it "matches only inside the record's own hotel" do
    other_hotel = create(:hotel)
    other_type = create(:room_type, hotel: other_hotel, room_number_mode: "custom", quantity: 1, room_numbers: %w[101])
    status = create(:room_status, hotel: other_hotel, room_type: other_type, room_number: "101")

    expect(status.room).to eq(other_hotel.rooms.find_by!(number: "101"))
    expect(status.room).not_to eq(room)
  end
end
