# frozen_string_literal: true

class HardenFolioRequiredFields < ActiveRecord::Migration[8.0]
  def up
    backfill_required_fields

    change_column_null :folio_transactions, :description, false
    change_column_null :folio_transactions, :currency, false
    change_column_null :booking_folios, :status, false
    change_column_default :booking_folios, :status, from: "open", to: "open"
  end

  def down
    change_column_null :booking_folios, :status, true
    change_column_null :folio_transactions, :currency, true
    change_column_null :folio_transactions, :description, true
  end

  private

  def backfill_required_fields
    execute <<~SQL.squish
      UPDATE folio_transactions
      SET description = 'Legacy folio transaction #' || id
      WHERE description IS NULL OR btrim(description) = ''
    SQL

    execute <<~SQL.squish
      UPDATE folio_transactions
      SET currency = COALESCE(NULLIF(bookings.currency, ''), NULLIF(hotels.default_currency, ''), 'MYR')
      FROM booking_folios
      JOIN bookings ON bookings.id = booking_folios.booking_id
      JOIN hotels ON hotels.id = booking_folios.hotel_id
      WHERE folio_transactions.booking_folio_id = booking_folios.id
        AND (folio_transactions.currency IS NULL OR btrim(folio_transactions.currency) = '')
    SQL

    execute <<~SQL.squish
      UPDATE folio_transactions
      SET currency = 'MYR'
      WHERE currency IS NULL OR btrim(currency) = ''
    SQL

    execute <<~SQL.squish
      UPDATE booking_folios
      SET status = 'open'
      WHERE status IS NULL OR btrim(status) = ''
    SQL
  end
end
