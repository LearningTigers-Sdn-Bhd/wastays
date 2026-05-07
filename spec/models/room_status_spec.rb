# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoomStatus, type: :model do
  it "requires a unique room number per hotel" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel)
    described_class.create!(hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    duplicate = described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:room_number]).to include("has already been taken")
  end

  it "allows the same room number in different hotels" do
    first_hotel = create(:hotel)
    second_hotel = create(:hotel)
    first_room_type = create(:room_type, hotel: first_hotel)
    second_room_type = create(:room_type, hotel: second_hotel)

    described_class.create!(hotel: first_hotel, room_type: first_room_type, room_number: "101", status: "ready")
    status = described_class.new(hotel: second_hotel, room_type: second_room_type, room_number: "101", status: "ready")

    expect(status).to be_valid
  end

  it "accepts only supported readiness statuses" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel)
    status = described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "unknown")

    expect(status).not_to be_valid
    expect(status.errors[:status]).to include("is not included in the list")
  end

  it "knows which statuses are normally assignable" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel)

    expect(described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "ready")).to be_assignable
    expect(described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")).not_to be_assignable
    expect(described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "preparing")).not_to be_assignable
    expect(described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "inspection_failed")).not_to be_assignable
    expect(described_class.new(hotel: hotel, room_type: room_type, room_number: "101", status: "out_of_service")).not_to be_assignable
  end
end
