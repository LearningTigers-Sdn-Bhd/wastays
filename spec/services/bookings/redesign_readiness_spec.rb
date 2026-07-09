# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RedesignReadiness do
  it "reports booking redesign data-quality counts" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel:)

    multi_room = create(:booking, hotel:, status: "confirmed")
    create(:booking_room, booking: multi_room, room_type:, quantity: 2)
    create(:booking_guest, booking: multi_room, is_primary: true)

    multiple_room_rows = create(:booking, hotel:, status: "confirmed")
    create(:booking_room, booking: multiple_room_rows, room_type:, quantity: 1)
    create(:booking_room, booking: multiple_room_rows, room_type:, quantity: 1)
    create(:booking_guest, booking: multiple_room_rows, is_primary: true)

    missing_primary = create(:booking, hotel:, status: "confirmed")
    create(:booking_room, booking: missing_primary, room_type:, quantity: 1)

    create(:booking, hotel:, status: "confirmed")

    expect(described_class.call).to include(
      multi_room_bookings: 2,
      bookings_with_multiple_room_rows: 1,
      duplicate_primary_guests: 0,
      missing_primary_guests: 2,
      duplicate_booking_guests: 0,
      bookings_without_rooms: 1
    )
  end
end
