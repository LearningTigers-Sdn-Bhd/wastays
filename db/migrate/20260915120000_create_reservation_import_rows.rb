# frozen_string_literal: true

class CreateReservationImportRows < ActiveRecord::Migration[8.1]
  def change
    create_table :reservation_import_rows do |t|
      t.references :reservation_import, null: false, foreign_key: true
      t.integer :sheet_row, null: false
      t.string :reservation_number, null: false
      t.string :status, null: false

      # The export's own values, kept verbatim so the preview shows the
      # operator what their file says rather than what we made of it.
      t.string :guest_name
      t.string :source
      t.string :room_number
      t.string :room_type_name
      t.string :rate_type
      t.datetime :booked_at
      t.string :booked_by
      t.date :arrival
      t.date :departure
      t.integer :adults, default: 0, null: false
      t.integer :children, default: 0, null: false
      t.integer :nights, default: 0, null: false
      t.decimal :total_amount, precision: 10, scale: 2
      t.decimal :amount_paid, precision: 10, scale: 2
      t.text :remark

      # What resolution made of the row. `issues` carries the field each problem
      # belongs to, so the table can point at the offending cell instead of
      # printing a sentence underneath and leaving the reader to map it back.
      t.jsonb :issues, null: false, default: []
      t.string :agency_name
      t.string :group_key
      t.bigint :room_type_id
      t.bigint :room_id
      t.bigint :booking_id

      t.timestamps
    end

    add_index :reservation_import_rows, [ :reservation_import_id, :status ],
              name: "idx_reservation_import_rows_on_import_and_status"
    add_index :reservation_import_rows, [ :reservation_import_id, :sheet_row ],
              name: "idx_reservation_import_rows_on_import_and_sheet_row", unique: true

    add_check_constraint :reservation_import_rows,
                         "status IN ('importable','imported','past','blocked','created','failed')",
                         name: "reservation_import_rows_status_allowed"
  end
end
