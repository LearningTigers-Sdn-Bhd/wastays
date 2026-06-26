# frozen_string_literal: true

class AddSharedFolioAccountReferences < ActiveRecord::Migration[8.0]
  def up
    add_column :bookings, :folio_account_reference, :string
    add_column :booking_folios, :folio_sequence, :integer

    backfill_folio_account_references!
    backfill_folio_sequences!

    add_index :bookings, [ :hotel_id, :folio_account_reference ],
      unique: true,
      where: "folio_account_reference IS NOT NULL",
      name: "idx_bookings_on_hotel_folio_account_reference"
    add_index :booking_folios, [ :booking_id, :folio_sequence ],
      unique: true,
      where: "folio_sequence IS NOT NULL",
      name: "idx_booking_folios_on_booking_folio_sequence"
  end

  def down
    remove_index :booking_folios, name: "idx_booking_folios_on_booking_folio_sequence"
    remove_index :bookings, name: "idx_bookings_on_hotel_folio_account_reference"
    remove_column :booking_folios, :folio_sequence
    remove_column :bookings, :folio_account_reference
  end

  private

  def backfill_folio_account_references!
    execute <<~SQL.squish
      WITH selected_folios AS (
        SELECT DISTINCT ON (booking_id)
          booking_id,
          folio_number
        FROM booking_folios
        WHERE folio_number IS NOT NULL
        ORDER BY booking_id, is_primary DESC, created_at ASC, id ASC
      )
      UPDATE bookings
      SET folio_account_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-3' || LPAD(selected_folios.folio_number::text, 7, '0')
      FROM selected_folios, hotels
      WHERE selected_folios.booking_id = bookings.id
        AND hotels.id = bookings.hotel_id
    SQL
  end

  def backfill_folio_sequences!
    execute <<~SQL.squish
      WITH sequenced_folios AS (
        SELECT
          id,
          ROW_NUMBER() OVER (
            PARTITION BY booking_id
            ORDER BY is_primary DESC, created_at ASC, id ASC
          ) AS sequence_number
        FROM booking_folios
      )
      UPDATE booking_folios
      SET folio_sequence = sequenced_folios.sequence_number
      FROM sequenced_folios
      WHERE sequenced_folios.id = booking_folios.id
    SQL
  end
end
