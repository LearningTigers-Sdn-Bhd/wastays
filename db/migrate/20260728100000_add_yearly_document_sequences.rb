# frozen_string_literal: true

class AddYearlyDocumentSequences < ActiveRecord::Migration[8.0]
  def up
    add_column :hotel_counters, :sequence_year, :integer
    add_column :bookings, :reservation_year, :integer
    add_column :bookings, :guest_registration_year, :integer
    add_column :bookings, :tourism_tax_voucher_year, :integer
    add_column :group_bookings, :reservation_year, :integer
    add_column :booking_folios, :folio_year, :integer
    add_column :booking_folios, :invoice_year, :integer
    add_column :ar_invoices, :invoice_year, :integer
    add_column :receipts, :receipt_year, :integer

    remove_index :hotel_counters, [ :hotel_id, :counter_type ]
    remove_index :bookings, name: :idx_bookings_on_hotel_reservation_number
    remove_index :bookings, name: :idx_bookings_on_hotel_tourism_tax_voucher_number
    remove_index :group_bookings, name: :idx_group_bookings_on_hotel_reservation_number
    remove_index :booking_folios, name: :index_booking_folios_on_hotel_id_and_folio_number
    remove_index :booking_folios, name: :index_booking_folios_on_hotel_id_and_invoice_number
    remove_index :ar_invoices, name: :index_ar_invoices_on_hotel_id_and_invoice_number
    remove_index :receipts, name: :index_receipts_on_hotel_id_and_receipt_number

    renumber_shared_reservations!
    renumber_bookings!(:guest_registration_number, :guest_registration_year, "COALESCE(checked_in_at, created_at)")
    renumber_bookings!(:tourism_tax_voucher_number, :tourism_tax_voucher_year, "updated_at")
    renumber_folios!
    renumber_folio_invoices!
    renumber_ar_invoices!
    renumber_receipts!
    refresh_references!

    execute "DELETE FROM hotel_counters"
    change_column_null :hotel_counters, :sequence_year, false

    add_index :hotel_counters, [ :hotel_id, :counter_type, :sequence_year ], unique: true, name: :idx_hotel_counters_type_year
    add_index :bookings, [ :hotel_id, :reservation_year, :reservation_number ], unique: true,
      where: "reservation_number IS NOT NULL", name: :idx_bookings_reservation_year_number
    add_index :bookings, [ :hotel_id, :guest_registration_year, :guest_registration_number ], unique: true,
      where: "guest_registration_number IS NOT NULL", name: :idx_bookings_guest_registration_year_number
    add_index :bookings, [ :hotel_id, :tourism_tax_voucher_year, :tourism_tax_voucher_number ], unique: true,
      where: "tourism_tax_voucher_number IS NOT NULL", name: :idx_bookings_tourism_voucher_year_number
    add_index :group_bookings, [ :hotel_id, :reservation_year, :reservation_number ], unique: true,
      name: :idx_group_bookings_reservation_year_number
    add_index :booking_folios, [ :hotel_id, :folio_year, :folio_number ], unique: true,
      name: :idx_booking_folios_folio_year_number
    add_index :booking_folios, [ :hotel_id, :invoice_year, :invoice_number ], unique: true,
      where: "invoice_number IS NOT NULL", name: :idx_booking_folios_invoice_year_number
    add_index :ar_invoices, [ :hotel_id, :invoice_year, :invoice_number ], unique: true,
      name: :idx_ar_invoices_invoice_year_number
    add_index :receipts, [ :hotel_id, :receipt_year, :receipt_number ], unique: true,
      name: :idx_receipts_year_number
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Historical document numbers were converted to yearly sequences"
  end

  private

  def renumber_shared_reservations!
    execute <<~SQL.squish
      WITH source AS (
        SELECT 'booking' AS owner_type, id, hotel_id, EXTRACT(YEAR FROM created_at)::integer AS sequence_year, created_at
        FROM bookings
        UNION ALL
        SELECT 'group', id, hotel_id, EXTRACT(YEAR FROM created_at)::integer, created_at
        FROM group_bookings
      ), ranked AS (
        SELECT owner_type, id, sequence_year,
               ROW_NUMBER() OVER (PARTITION BY hotel_id, sequence_year ORDER BY created_at, owner_type, id) AS sequence_number
        FROM source
      )
      UPDATE bookings SET reservation_year = ranked.sequence_year, reservation_number = ranked.sequence_number
      FROM ranked WHERE ranked.owner_type = 'booking' AND bookings.id = ranked.id
    SQL
    execute <<~SQL.squish
      WITH source AS (
        SELECT 'booking' AS owner_type, id, hotel_id, EXTRACT(YEAR FROM created_at)::integer AS sequence_year, created_at
        FROM bookings
        UNION ALL
        SELECT 'group', id, hotel_id, EXTRACT(YEAR FROM created_at)::integer, created_at
        FROM group_bookings
      ), ranked AS (
        SELECT owner_type, id, sequence_year,
               ROW_NUMBER() OVER (PARTITION BY hotel_id, sequence_year ORDER BY created_at, owner_type, id) AS sequence_number
        FROM source
      )
      UPDATE group_bookings SET reservation_year = ranked.sequence_year, reservation_number = ranked.sequence_number
      FROM ranked WHERE ranked.owner_type = 'group' AND group_bookings.id = ranked.id
    SQL
  end

  def renumber_bookings!(number_column, year_column, timestamp_expression)
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id, EXTRACT(YEAR FROM #{timestamp_expression})::integer AS sequence_year,
               ROW_NUMBER() OVER (
                 PARTITION BY hotel_id, EXTRACT(YEAR FROM #{timestamp_expression})
                 ORDER BY #{timestamp_expression}, id
               ) AS sequence_number
        FROM bookings WHERE #{number_column} IS NOT NULL
      )
      UPDATE bookings SET #{year_column} = ranked.sequence_year, #{number_column} = ranked.sequence_number
      FROM ranked WHERE bookings.id = ranked.id
    SQL
  end

  def renumber_folios!
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id, EXTRACT(YEAR FROM opened_at)::integer AS sequence_year,
               ROW_NUMBER() OVER (PARTITION BY hotel_id, EXTRACT(YEAR FROM opened_at) ORDER BY opened_at, id) AS sequence_number
        FROM booking_folios
      )
      UPDATE booking_folios SET folio_year = ranked.sequence_year, folio_number = ranked.sequence_number
      FROM ranked WHERE booking_folios.id = ranked.id
    SQL
  end

  def renumber_folio_invoices!
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id, EXTRACT(YEAR FROM COALESCE(closed_at, updated_at))::integer AS sequence_year,
               ROW_NUMBER() OVER (
                 PARTITION BY hotel_id, EXTRACT(YEAR FROM COALESCE(closed_at, updated_at))
                 ORDER BY COALESCE(closed_at, updated_at), id
               ) AS sequence_number
        FROM booking_folios WHERE invoice_number IS NOT NULL
      )
      UPDATE booking_folios SET invoice_year = ranked.sequence_year, invoice_number = ranked.sequence_number
      FROM ranked WHERE booking_folios.id = ranked.id
    SQL
  end

  def renumber_ar_invoices!
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id, EXTRACT(YEAR FROM issued_on)::integer AS sequence_year,
               ROW_NUMBER() OVER (PARTITION BY hotel_id, EXTRACT(YEAR FROM issued_on) ORDER BY issued_on, id) AS sequence_number
        FROM ar_invoices
      )
      UPDATE ar_invoices SET invoice_year = ranked.sequence_year, invoice_number = ranked.sequence_number
      FROM ranked WHERE ar_invoices.id = ranked.id
    SQL
  end

  def renumber_receipts!
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id, EXTRACT(YEAR FROM issued_at)::integer AS sequence_year,
               ROW_NUMBER() OVER (PARTITION BY hotel_id, EXTRACT(YEAR FROM issued_at) ORDER BY issued_at, id) AS sequence_number
        FROM receipts
      )
      UPDATE receipts SET receipt_year = ranked.sequence_year, receipt_number = ranked.sequence_number
      FROM ranked WHERE receipts.id = ranked.id
    SQL
  end

  def refresh_references!
    execute <<~SQL.squish
      UPDATE bookings SET
        reservation_reference = hotels.hotel_prefix || '-' || RIGHT(reservation_year::text, 2) || '1' || LPAD(reservation_number::text, 5, '0'),
        guest_registration_reference = CASE WHEN guest_registration_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-' || RIGHT(guest_registration_year::text, 2) || '2' || LPAD(guest_registration_number::text, 5, '0') END,
        tourism_tax_voucher_reference = CASE WHEN tourism_tax_voucher_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-' || RIGHT(tourism_tax_voucher_year::text, 2) || '6' || LPAD(tourism_tax_voucher_number::text, 5, '0') END
      FROM hotels WHERE bookings.hotel_id = hotels.id
    SQL
    execute <<~SQL.squish
      UPDATE group_bookings SET reservation_reference = hotels.hotel_prefix || '-' || RIGHT(reservation_year::text, 2) || '1' || LPAD(reservation_number::text, 5, '0')
      FROM hotels WHERE group_bookings.hotel_id = hotels.id
    SQL
    execute <<~SQL.squish
      UPDATE booking_folios SET invoice_reference = CASE WHEN invoice_number IS NULL THEN NULL ELSE hotels.hotel_prefix || '-' || RIGHT(invoice_year::text, 2) || '7' || LPAD(invoice_number::text, 5, '0') END
      FROM hotels WHERE booking_folios.hotel_id = hotels.id
    SQL
    execute <<~SQL.squish
      UPDATE ar_invoices SET invoice_reference = hotels.hotel_prefix || '-' || RIGHT(invoice_year::text, 2) || '4' || LPAD(invoice_number::text, 5, '0')
      FROM hotels WHERE ar_invoices.hotel_id = hotels.id
    SQL
    execute <<~SQL.squish
      UPDATE receipts SET public_number = hotels.hotel_prefix || '-' || RIGHT(receipt_year::text, 2) || '5' || LPAD(receipt_number::text, 5, '0')
      FROM hotels WHERE receipts.hotel_id = hotels.id
    SQL
    execute <<~SQL.squish
      UPDATE bookings SET folio_account_reference = folio_refs.reference
      FROM (
        SELECT DISTINCT ON (booking_folios.booking_id) booking_folios.booking_id,
          hotels.hotel_prefix || '-' || RIGHT(booking_folios.folio_year::text, 2) || '3' || LPAD(booking_folios.folio_number::text, 5, '0') AS reference
        FROM booking_folios
        INNER JOIN hotels ON hotels.id = booking_folios.hotel_id
        ORDER BY booking_folios.booking_id, booking_folios.is_primary DESC, booking_folios.opened_at, booking_folios.id
      ) folio_refs WHERE bookings.id = folio_refs.booking_id
    SQL
  end
end
