# frozen_string_literal: true

class CreateGroupBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :group_bookings do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :organizer_guest, null: true, foreign_key: { to_table: :guests }
      t.string :reference, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "active"
      t.string :source
      t.string :external_reference
      t.date :default_check_in
      t.date :default_check_out
      t.text :notes
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :group_bookings, [ :hotel_id, :reference ], unique: true
    add_index :group_bookings, [ :hotel_id, :status ]
    add_check_constraint :group_bookings,
      "status IN ('draft', 'active', 'completed', 'cancelled')",
      name: "group_bookings_status_allowed"

    add_reference :bookings, :group_booking, null: true, foreign_key: true, index: true
    add_column :bookings, :group_position, :integer
    add_index :bookings,
      [ :group_booking_id, :group_position ],
      unique: true,
      where: "group_booking_id IS NOT NULL",
      name: "idx_bookings_group_position"
  end
end
