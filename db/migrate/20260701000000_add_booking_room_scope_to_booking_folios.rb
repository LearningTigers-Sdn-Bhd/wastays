# frozen_string_literal: true

class AddBookingRoomScopeToBookingFolios < ActiveRecord::Migration[8.0]
  def up
    # Existing folios intentionally remain booking-level. We do not infer room ownership
    # for either single-room or multi-room bookings because that would guess at billing intent.
    add_reference :booking_folios,
      :booking_room,
      null: true,
      index: true,
      foreign_key: { on_delete: :restrict }

    remove_index :booking_folios, name: "index_booking_folios_on_primary_booking"
    add_index :booking_folios,
      :booking_id,
      unique: true,
      where: "is_primary AND booking_room_id IS NULL",
      name: "idx_booking_folios_primary_at_booking_level"
    add_index :booking_folios,
      [ :booking_id, :booking_room_id ],
      unique: true,
      where: "is_primary AND booking_room_id IS NOT NULL",
      name: "idx_booking_folios_primary_per_room"
  end

  def down
    # Removing room scope collapses all primaries back to booking scope. Prefer the
    # booking-level primary, then deterministically retain the oldest remaining primary.
    execute <<~SQL.squish
      WITH ranked_primaries AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY booking_id
                 ORDER BY (booking_room_id IS NULL) DESC, opened_at ASC, id ASC
               ) AS primary_rank
        FROM booking_folios
        WHERE is_primary = TRUE
      )
      UPDATE booking_folios
      SET is_primary = FALSE,
          updated_at = CURRENT_TIMESTAMP
      FROM ranked_primaries
      WHERE booking_folios.id = ranked_primaries.id
        AND ranked_primaries.primary_rank > 1
    SQL

    remove_index :booking_folios, name: "idx_booking_folios_primary_per_room"
    remove_index :booking_folios, name: "idx_booking_folios_primary_at_booking_level"
    remove_reference :booking_folios, :booking_room, foreign_key: true, index: true
    add_index :booking_folios,
      [ :booking_id, :is_primary ],
      unique: true,
      where: "is_primary",
      name: "index_booking_folios_on_primary_booking"
  end
end
