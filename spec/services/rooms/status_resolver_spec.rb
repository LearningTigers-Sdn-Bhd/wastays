# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::StatusResolver do
  it "returns occupied when a checked-in booking overlaps today" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    booking = create(:booking, hotel: hotel, status: "checked_in", check_in: Date.current, check_out: Date.tomorrow, checked_in_at: Time.current)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101", subtotal: 200)
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    result = described_class.new(hotel: hotel, room_type: room_type, room_number: "101", date: Date.current).call

    expect(result.status).to eq("occupied")
    expect(result.assignable).to be(false)
  end

  it "returns persisted readiness status when the room is not occupied" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel, room_numbers: [ "101" ])
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    result = described_class.new(hotel: hotel, room_type: room_type, room_number: "101", date: Date.current).call

    expect(result.status).to eq("dirty")
    expect(result.assignable).to be(false)
  end

  describe "the stay the room is shown against" do
    let(:hotel) { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ]) }

    def resolve
      described_class.new(hotel: hotel, room_type: room_type, room_number: "101", date: Date.current).call
    end

    def booking_on(status)
      create(:booking, hotel: hotel, status: status, check_in: Date.current, check_out: Date.tomorrow).tap do |booking|
        create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      end
    end

    it "is whoever is in the room" do
      booking = booking_on("checked_in")

      expect(resolve.active_booking).to eq(booking)
    end

    it "is whoever was last in it once the stay is over" do
      booking = booking_on("completed")

      expect(resolve.active_booking).to eq(booking)
    end

    it "is nobody when the room stood empty" do
      expect(resolve.active_booking).to be_nil
    end

    it "refuses a question it cannot answer, rather than answering nil" do
      expect { resolve.public_send(:housekeeper) }.to raise_error(NoMethodError)
    end
  end
end
