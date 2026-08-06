# frozen_string_literal: true

class AddDocumentReferenceSnapshotsAndReceipts < ActiveRecord::Migration[8.0]
  def up
    assign_missing_hotel_prefixes!

    create_table :hotel_prefix_histories do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :prefix, null: false
      t.datetime :retired_at
      t.timestamps
    end
    add_index :hotel_prefix_histories, :prefix, unique: true
    add_index :hotel_prefix_histories, [ :hotel_id, :prefix ], unique: true

    add_column :bookings, :reservation_reference, :string
    add_column :bookings, :guest_registration_reference, :string
    add_column :bookings, :tourism_tax_voucher_reference, :string
    add_column :group_bookings, :reservation_reference, :string
    add_column :booking_folios, :invoice_reference, :string
    add_column :ar_invoices, :invoice_reference, :string

    add_index :bookings, [ :hotel_id, :reservation_reference ], unique: true, where: "reservation_reference IS NOT NULL"
    add_index :bookings, [ :hotel_id, :guest_registration_reference ], unique: true, where: "guest_registration_reference IS NOT NULL"
    add_index :bookings, [ :hotel_id, :tourism_tax_voucher_reference ], unique: true, where: "tourism_tax_voucher_reference IS NOT NULL"
    add_index :group_bookings, [ :hotel_id, :reservation_reference ], unique: true, where: "reservation_reference IS NOT NULL"
    add_index :booking_folios, [ :hotel_id, :invoice_reference ], unique: true, where: "invoice_reference IS NOT NULL"
    add_index :ar_invoices, [ :hotel_id, :invoice_reference ], unique: true, where: "invoice_reference IS NOT NULL"

    create_table :receipts do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :folio_transaction, foreign_key: true, index: false
      t.references :deposit, foreign_key: true, index: false
      t.references :ar_payment, foreign_key: true, index: false
      t.references :payment_transaction, foreign_key: true
      t.integer :receipt_number, null: false
      t.string :public_number, null: false
      t.string :access_token, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false
      t.string :payment_method, null: false
      t.string :external_reference
      t.datetime :received_at, null: false
      t.datetime :issued_at, null: false
      t.string :status, null: false, default: "issued"
      t.jsonb :payer_snapshot, null: false, default: {}
      t.jsonb :context_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :receipts, [ :hotel_id, :receipt_number ], unique: true
    add_index :receipts, :public_number, unique: true
    add_index :receipts, :access_token, unique: true
    add_index :receipts, :folio_transaction_id, unique: true, where: "folio_transaction_id IS NOT NULL"
    add_index :receipts, :deposit_id, unique: true, where: "deposit_id IS NOT NULL"
    add_index :receipts, :ar_payment_id, unique: true, where: "ar_payment_id IS NOT NULL"
    add_check_constraint :receipts,
      "num_nonnulls(folio_transaction_id, deposit_id, ar_payment_id) = 1",
      name: "receipts_exactly_one_source"
    add_check_constraint :receipts, "amount > 0", name: "receipts_amount_positive"
    add_check_constraint :receipts, "status IN ('issued', 'voided')", name: "receipts_status_allowed"

    change_column_null :group_bookings, :receipt_number, true

    execute <<~SQL.squish
      INSERT INTO hotel_prefix_histories (hotel_id, prefix, created_at, updated_at)
      SELECT id, hotel_prefix, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM hotels
      ON CONFLICT (prefix) DO NOTHING
    SQL

    execute <<~SQL.squish
      UPDATE bookings
      SET reservation_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-1' || LPAD(bookings.reservation_number::text, 7, '0')
      FROM hotels
      WHERE bookings.hotel_id = hotels.id AND bookings.reservation_number IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE bookings
      SET guest_registration_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-2' || LPAD(bookings.guest_registration_number::text, 7, '0')
      FROM hotels
      WHERE bookings.hotel_id = hotels.id AND bookings.guest_registration_number IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE bookings
      SET tourism_tax_voucher_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-6' || LPAD(bookings.tourism_tax_voucher_number::text, 7, '0')
      FROM hotels
      WHERE bookings.hotel_id = hotels.id AND bookings.tourism_tax_voucher_number IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE group_bookings
      SET reservation_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-1' || LPAD(group_bookings.reservation_number::text, 7, '0')
      FROM hotels
      WHERE group_bookings.hotel_id = hotels.id AND group_bookings.reservation_number IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE booking_folios
      SET invoice_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-7' || LPAD(booking_folios.invoice_number::text, 7, '0')
      FROM hotels
      WHERE booking_folios.hotel_id = hotels.id AND booking_folios.invoice_number IS NOT NULL
    SQL
    execute <<~SQL.squish
      UPDATE ar_invoices
      SET invoice_reference = COALESCE(NULLIF(hotels.hotel_prefix, ''), 'WS') || '-4' || LPAD(ar_invoices.invoice_number::text, 7, '0')
      FROM hotels
      WHERE ar_invoices.hotel_id = hotels.id
    SQL
  end

  def down
    execute <<~SQL.squish
      WITH numbered AS (
        SELECT group_bookings.id,
               COALESCE(existing.maximum, 0) + ROW_NUMBER() OVER (PARTITION BY group_bookings.hotel_id ORDER BY group_bookings.id) AS replacement
        FROM group_bookings
        LEFT JOIN (
          SELECT hotel_id, MAX(value) AS maximum
          FROM (
            SELECT hotel_id, receipt_number AS value FROM bookings WHERE receipt_number IS NOT NULL
            UNION ALL
            SELECT hotel_id, receipt_number AS value FROM group_bookings WHERE receipt_number IS NOT NULL
          ) values_by_hotel
          GROUP BY hotel_id
        ) existing ON existing.hotel_id = group_bookings.hotel_id
        WHERE group_bookings.receipt_number IS NULL
      )
      UPDATE group_bookings SET receipt_number = numbered.replacement
      FROM numbered WHERE group_bookings.id = numbered.id
    SQL
    change_column_null :group_bookings, :receipt_number, false
    drop_table :receipts
    remove_column :ar_invoices, :invoice_reference
    remove_column :booking_folios, :invoice_reference
    remove_column :group_bookings, :reservation_reference
    remove_column :bookings, :tourism_tax_voucher_reference
    remove_column :bookings, :guest_registration_reference
    remove_column :bookings, :reservation_reference
    drop_table :hotel_prefix_histories
  end

  private

  def assign_missing_hotel_prefixes!
    used = select_values("SELECT hotel_prefix FROM hotels WHERE hotel_prefix IS NOT NULL AND hotel_prefix <> ''").to_set
    select_values("SELECT id FROM hotels WHERE hotel_prefix IS NULL OR hotel_prefix = '' ORDER BY id").each do |id|
      candidate = "H#{id.to_i.to_s(36).upcase.rjust(2, '0')}"
      candidate = "H#{SecureRandom.alphanumeric(5).upcase}" while used.include?(candidate)
      used << candidate
      execute "UPDATE hotels SET hotel_prefix = #{quote(candidate)} WHERE id = #{quote(id)}"
    end
  end
end
