# frozen_string_literal: true

class AddGroupFolioMovementSupport < ActiveRecord::Migration[8.1]
  def up
    %i[folio_transactions folio_forecasted_charges].each do |table|
      add_reference table, :source_booking, foreign_key: { to_table: :bookings }
      execute <<~SQL
        UPDATE #{table} SET source_booking_id = booking_folios.booking_id
        FROM booking_folios WHERE #{table}.booking_folio_id = booking_folios.id
      SQL
      change_column_null table, :source_booking_id, false
    end
    remove_index :folio_forecasted_charges, name: "idx_forecasted_charges_on_unique_forecast"
    add_index :folio_forecasted_charges, %i[source_booking_id booking_folio_id charge_kind identity stay_date],
      unique: true, where: "status = 'forecast'", name: "idx_forecasts_source_folio_identity"

    create_table :folio_transfer_batches do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :idempotency_key, null: false
      t.string :request_fingerprint, null: false
      t.jsonb :result_transaction_ids, null: false, default: []
      t.datetime :completed_at
      t.timestamps
    end
    add_index :folio_transfer_batches, %i[hotel_id idempotency_key], unique: true
  end

  def down
    drop_table :folio_transfer_batches
    remove_index :folio_forecasted_charges, name: "idx_forecasts_source_folio_identity"
    add_index :folio_forecasted_charges, %i[booking_folio_id charge_kind identity stay_date],
      unique: true, where: "status = 'forecast'", name: "idx_forecasted_charges_on_unique_forecast"
    %i[folio_transactions folio_forecasted_charges].each { |table| remove_reference table, :source_booking, foreign_key: { to_table: :bookings } }
  end
end
