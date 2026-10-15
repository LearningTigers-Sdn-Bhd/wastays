# frozen_string_literal: true

# Lets the reservation importer read more than one eZee report layout. The row
# carries what a layout can supply that the original Reservation List could not:
# a booking status, the boat transfer parsed from the remarks, an explicit
# source key, and any staff-facing note the adapter wants kept.
class AddLayoutColumnsToReservationImports < ActiveRecord::Migration[8.1]
  def change
    add_column :reservation_imports, :source_layout, :string

    change_table :reservation_import_rows, bulk: true do |t|
      t.string :booking_status, null: false, default: "confirmed"
      t.string :source_key
      t.text :internal_note
      t.string :boat_in_type
      t.string :boat_in_time
      t.string :boat_out_type
      t.string :boat_out_time
      t.bigint :rate_plan_id
    end

    add_check_constraint :reservation_import_rows,
                         "booking_status IN ('confirmed', 'pending', 'cancelled')",
                         name: "reservation_import_rows_booking_status_allowed"
  end
end
