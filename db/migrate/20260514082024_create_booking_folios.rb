class CreateBookingFolios < ActiveRecord::Migration[8.0]
  def up
    create_table :booking_folios do |t|
      t.references :booking, null: false, foreign_key: true, index: { unique: true }
      t.integer :folio_number
      t.string :status, default: "open"

      t.timestamps
    end

    add_index :booking_folios, :folio_number

    # Migrate existing data
    execute <<-SQL
      INSERT INTO booking_folios (booking_id, folio_number, status, created_at, updated_at)
      SELECT id, folio_number, 'open', NOW(), NOW()
      FROM bookings
      WHERE folio_number IS NOT NULL
    SQL

    remove_column :bookings, :folio_number, :integer
  end

  def down
    add_column :bookings, :folio_number, :integer

    # Rollback data
    execute <<-SQL
      UPDATE bookings
      SET folio_number = booking_folios.folio_number
      FROM booking_folios
      WHERE bookings.id = booking_folios.booking_id
    SQL

    drop_table :booking_folios
  end
end
