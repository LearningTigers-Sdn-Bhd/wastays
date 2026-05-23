class ScopeBookingFolioNumbersToHotels < ActiveRecord::Migration[8.0]
  def up
    add_reference :booking_folios, :hotel, foreign_key: true

    execute <<~SQL.squish
      UPDATE booking_folios
      SET hotel_id = bookings.hotel_id
      FROM bookings
      WHERE booking_folios.booking_id = bookings.id
    SQL

    change_column_null :booking_folios, :hotel_id, false

    remove_index :booking_folios, :folio_number if index_exists?(:booking_folios, :folio_number)
    add_index :booking_folios, [ :hotel_id, :folio_number ], unique: true
  end

  def down
    remove_index :booking_folios, [ :hotel_id, :folio_number ] if index_exists?(:booking_folios, [ :hotel_id, :folio_number ])
    add_index :booking_folios, :folio_number unless index_exists?(:booking_folios, :folio_number)
    remove_reference :booking_folios, :hotel, foreign_key: true
  end
end
