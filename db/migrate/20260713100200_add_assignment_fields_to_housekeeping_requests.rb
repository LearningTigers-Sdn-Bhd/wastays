class AddAssignmentFieldsToHousekeepingRequests < ActiveRecord::Migration[8.0]
  def up
    change_column_null :housekeeping_requests, :booking_id, true

    add_reference :housekeeping_requests, :hotel unless column_exists?(:housekeeping_requests, :hotel_id)
    add_reference :housekeeping_requests, :room_type unless column_exists?(:housekeeping_requests, :room_type_id)
    add_column :housekeeping_requests, :room_number, :string unless column_exists?(:housekeeping_requests, :room_number)

    add_foreign_key :housekeeping_requests, :hotels unless foreign_key_exists?(:housekeeping_requests, :hotels)
    add_foreign_key :housekeeping_requests, :room_types unless foreign_key_exists?(:housekeeping_requests, :room_types)
    add_index :housekeeping_requests, [ :hotel_id, :status ] unless index_exists?(:housekeeping_requests, [ :hotel_id, :status ])
    add_index :housekeeping_requests, [ :hotel_id, :room_number ] unless index_exists?(:housekeeping_requests, [ :hotel_id, :room_number ])

    execute <<~SQL.squish
      UPDATE housekeeping_requests
      SET hotel_id = bookings.hotel_id
      FROM bookings
      WHERE housekeeping_requests.booking_id = bookings.id
        AND housekeeping_requests.hotel_id IS NULL
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "assignment fields may predate this reconciliation migration"
  end
end
