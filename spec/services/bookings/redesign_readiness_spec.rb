# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::RedesignReadiness do
  before(:context) do
    connection = ActiveRecord::Base.connection
    connection.remove_index(:booking_rooms, name: "idx_booking_rooms_unique_booking") if
      connection.index_exists?(:booking_rooms, :booking_id, name: "idx_booking_rooms_unique_booking")
  end

  after(:context) do
    connection = ActiveRecord::Base.connection
    connection.add_index(:booking_rooms, :booking_id, unique: true, name: "idx_booking_rooms_unique_booking") unless
      connection.index_exists?(:booking_rooms, :booking_id, name: "idx_booking_rooms_unique_booking")
  end

  it "reports booking redesign data-quality counts" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel:)

    multiple_room_rows = create(:booking, hotel:, status: "confirmed")
    create(:booking_room, booking: multiple_room_rows, room_type:)
    BookingRoom.insert!({ booking_id: multiple_room_rows.id, room_type_id: room_type.id, subtotal: 200,
      room_type_snapshot: {}, nightly_rate_snapshot: {}, occupancy_snapshot: {}, created_at: Time.current, updated_at: Time.current })
    create(:booking_guest, booking: multiple_room_rows, is_primary: true)

    missing_primary = create(:booking, hotel:, status: "confirmed")
    create(:booking_room, booking: missing_primary, room_type:)

    create(:booking, hotel:, status: "confirmed")
    create(:booking, hotel:, status: "pending")

    blocked = create(:booking, hotel:, status: "confirmed")
    create(:booking_room, booking: blocked, room_type:)
    BookingRoom.insert!({ booking_id: blocked.id, room_type_id: room_type.id, subtotal: 200,
      room_type_snapshot: {}, nightly_rate_snapshot: {}, occupancy_snapshot: {}, created_at: Time.current, updated_at: Time.current })
    create(:payment_transaction, booking: blocked)

    external = create(:booking, hotel:, status: "confirmed", source: "ota")
    create(:booking_room, booking: external, room_type:)
    BookingRoom.insert!({ booking_id: external.id, room_type_id: room_type.id, subtotal: 200,
      room_type_snapshot: {}, nightly_rate_snapshot: {}, occupancy_snapshot: {}, created_at: Time.current, updated_at: Time.current })

    expect(described_class.call).to include(
      bookings_with_multiple_room_rows: 3,
      ungrouped_multi_room_bookings: 3,
      already_grouped_multi_room_bookings: 0,
      multi_room_finance_blockers: 1,
      multi_room_external_blockers: 1,
      multi_room_ready_to_split: 3,
      multi_room_requiring_anchor_review: 2,
      duplicate_primary_guests: 0,
      missing_primary_guests: 4,
      duplicate_booking_guests: 0,
      bookings_without_rooms: 2,
      pending_bookings_without_rooms: 1,
      non_pending_bookings_without_rooms: 1
    )
  end
end
