# frozen_string_literal: true

class EnforceOneBookingRoomPerBooking < ActiveRecord::Migration[8.0]
  def up
    split_legacy_bookings!
    duplicates = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM (
        SELECT booking_id
        FROM booking_rooms
        GROUP BY booking_id
        HAVING COUNT(*) > 1
      ) duplicate_bookings
    SQL

    if duplicates.positive?
      raise ActiveRecord::MigrationError,
        "#{duplicates} multi-room booking(s) remain. Run bookings:redesign:split_legacy_multi_room before this migration."
    end

    add_index :booking_rooms, :booking_id, unique: true, name: "idx_booking_rooms_unique_booking"
  end

  def down
    remove_index :booking_rooms, name: "idx_booking_rooms_unique_booking"
  end

  private

  def split_legacy_bookings!
    booking_ids = Booking.joins(:booking_rooms)
      .where(group_booking_id: nil)
      .group("bookings.id")
      .having("COUNT(booking_rooms.id) > 1")
      .pluck(:id)

    booking_ids.each do |booking_id|
      result = Bookings::SplitLegacyMultiRoom.call(
        booking: Booking.find(booking_id),
        metadata: { source: self.class.name }
      )
      raise ActiveRecord::MigrationError, "Booking #{booking_id} could not be split: #{result.error}" unless result.success?
    end
  end
end
