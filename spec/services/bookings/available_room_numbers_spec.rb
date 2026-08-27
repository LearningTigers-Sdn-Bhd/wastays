# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::AvailableRoomNumbers do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 3, room_numbers: [ "101", "102", "103" ]) }
  let(:check_in) { Date.current }
  let(:check_out) { Date.current + 1.day }

  subject { described_class.new(hotel: hotel, room_type: room_type, check_in: check_in, check_out: check_out) }

  it "returns all room numbers when no bookings exist" do
    expect(subject.call).to match_array([ "101", "102", "103" ])
  end

  it "excludes room numbers already occupied" do
    booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    expect(subject.call).to match_array([ "102", "103" ])
  end

  it "keeps room numbers reserved while a no-show is detected" do
    booking = create(
      :booking,
      hotel: hotel,
      check_in: check_in,
      check_out: check_out,
      status: "no_show_detected",
      no_show_detected_business_date: check_in
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    expect(subject.call).to match_array([ "102", "103" ])
  end

  it "includes room numbers of excluded booking id (for editing)" do
    booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    service = described_class.new(hotel: hotel, room_type: room_type, check_in: check_in, check_out: check_out, exclude_booking_id: booking.id)
    expect(service.call).to match_array([ "101", "102", "103" ])
  end

  it "excludes occupied room numbers from booking_rooms assignments" do
    booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "102")

    expect(subject.call).to match_array([ "101", "103" ])
  end

  it "excludes room numbers locked by other users for the same room type" do
    other_user = create(:user)
    create(:room_lock, hotel: hotel, room_type: room_type, user: other_user, room_number: "102", expires_at: 10.minutes.from_now)

    expect(subject.call).to match_array([ "101", "103" ])
  end

  it "includes room numbers locked for different room types" do
    other_room_type = create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "201" ])
    other_user = create(:user)
    create(:room_lock, hotel: hotel, room_type: other_room_type, user: other_user, room_number: "201", expires_at: 10.minutes.from_now)

    expect(subject.call).to match_array([ "101", "102", "103" ])
  end

  it "includes room numbers locked by the current user" do
    user = create(:user)
    Current.user_id = user.id
    create(:room_lock, hotel: hotel, room_type: room_type, user: user, room_number: "102", expires_at: 10.minutes.from_now)

    expect(subject.call).to match_array([ "101", "102", "103" ])
  ensure
    Current.user_id = nil
  end

  it "treats open inventory with blank available_room_numbers as all room numbers (quantity mode)" do
    create(:room_inventory, room_type: room_type, date: check_in, status: "open", quantity: 2, available_room_numbers: [])

    expect(subject.call).to match_array([ "101", "102", "103" ])
  end

  describe "#options" do
    it "returns non-ready rooms as non-selectable options with labels" do
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

      options = described_class.new(
        hotel: hotel,
        room_type: room_type,
        check_in: check_in,
        check_out: check_out
      ).options

      dirty_option = options.find { |opt| opt[:room_number] == "101" }
      ready_option = options.find { |opt| opt[:room_number] == "102" }

      expect(dirty_option[:selectable]).to be(false)
      expect(dirty_option[:label]).to eq("101 (Dirty)")
      expect(ready_option[:selectable]).to be(true)
    end
  end
end
