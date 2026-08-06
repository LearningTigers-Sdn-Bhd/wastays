# frozen_string_literal: true

# Retires the jsonb timetable. hotel_boat_schedules has been the only source
# since CreateHotelBoatTables, and no application code reads these columns.
#
# The rollback restores the columns but not their contents: the backfill that
# seeded hotel_boat_schedules read from here, so once this runs the original
# arrays are gone. Re-deriving them from the slot rows is the way back, not
# this migration.
class DropBoatTimesFromHotels < ActiveRecord::Migration[8.0]
  def up
    remove_column :hotels, :boat_in_times
    remove_column :hotels, :boat_out_times
  end

  def down
    add_column :hotels, :boat_in_times, :jsonb, default: [], null: false
    add_column :hotels, :boat_out_times, :jsonb, default: [], null: false

    # Rebuild from the live timetable so a rollback lands on usable data rather
    # than empty arrays.
    execute(<<~SQL.squish)
      UPDATE hotels SET
        boat_in_times = COALESCE((
          SELECT jsonb_agg(to_char(s.time, 'HH24:MI') ORDER BY s.time)
          FROM hotel_boat_schedules s
          WHERE s.hotel_id = hotels.id AND s.kind = 'boat_in' AND s.archived_at IS NULL
        ), '[]'::jsonb),
        boat_out_times = COALESCE((
          SELECT jsonb_agg(to_char(s.time, 'HH24:MI') ORDER BY s.time)
          FROM hotel_boat_schedules s
          WHERE s.hotel_id = hotels.id AND s.kind = 'boat_out' AND s.archived_at IS NULL
        ), '[]'::jsonb)
    SQL
  end
end
