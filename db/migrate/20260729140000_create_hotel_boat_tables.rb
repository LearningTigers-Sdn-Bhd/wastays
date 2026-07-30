# frozen_string_literal: true

# Moves the daily boat timetable off the two hotels jsonb columns and onto rows,
# so each slot can carry its own meal entitlements instead of the report
# deriving them from hardcoded hours.
#
# hotels.boat_in_times / boat_out_times stay in place for one release; the
# backfill lives in the next migration.
class CreateHotelBoatTables < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_boat_settings do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }
      t.time :breakfast_time
      t.time :lunch_time
      t.time :dinner_time
      t.timestamps
    end

    create_table :hotel_boat_schedules do |t|
      t.references :hotel, null: false, foreign_key: true
      t.time :time, null: false
      t.string :kind, null: false
      t.boolean :has_breakfast, null: false, default: false
      t.boolean :has_lunch, null: false, default: false
      t.boolean :has_dinner, null: false, default: false
      # Slots are retired, never destroyed: a guest already booked on a dropped
      # slot still needs it to explain their meals.
      t.datetime :archived_at
      t.timestamps

      t.index %i[hotel_id kind time], unique: true
      t.index %i[hotel_id kind archived_at]
    end

    add_check_constraint :hotel_boat_schedules,
                         "kind IN ('boat_in', 'boat_out')",
                         name: "hotel_boat_schedules_kind_check"
  end
end
