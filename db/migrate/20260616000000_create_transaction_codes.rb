# frozen_string_literal: true

class CreateTransactionCodes < ActiveRecord::Migration[8.0]
  class MigrationHotel < ActiveRecord::Base
    self.table_name = "hotels"
  end

  class MigrationHotelTax < ActiveRecord::Base
    self.table_name = "hotel_taxes"
  end

  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  DEFAULT_CODES = [
    { system_key: "room_revenue", code: "ROOM", name: "Room Revenue", kind: "charge", category: "accommodation", gl_account_code: "4010" },
    { system_key: "no_show_revenue", code: "NO_SHOW", name: "No-Show Revenue", kind: "charge", category: "no_show_charge", gl_account_code: "4030" },
    { system_key: "cancel_revenue", code: "CANCEL", name: "Cancellation Revenue", kind: "charge", category: "cancellation_charge", gl_account_code: "4033" },
    { system_key: "sst_tax", code: "TAX_SST", name: "SST", kind: "tax", category: "tax", gl_account_code: "2010" },
    { system_key: "tourism_tax", code: "TAX_TTX", name: "Tourism Tax", kind: "tax", category: "tax", gl_account_code: "2010" },
    { system_key: "fnb_revenue", code: "FNB", name: "Food & Beverage", kind: "charge", category: "fb", gl_account_code: "4020" },
    { system_key: "parking_revenue", code: "PARK", name: "Parking", kind: "charge", category: "parking", gl_account_code: "4090" },
    { system_key: "misc_revenue", code: "MISC", name: "Miscellaneous Revenue", kind: "charge", category: "other", gl_account_code: "4090" },
    { system_key: "cash_payment", code: "CASH", name: "Cash Payment", kind: "payment", category: "cash", gl_account_code: "1020" },
    { system_key: "card_payment", code: "CARD", name: "Card Payment", kind: "payment", category: "gateway_payment", gl_account_code: "1010" },
    { system_key: "bank_payment", code: "BANK", name: "Bank Transfer Payment", kind: "payment", category: "booking_payment", gl_account_code: "2020" },
    { system_key: "refund", code: "REFUND", name: "Refund", kind: "payment", category: "refund", gl_account_code: "1030" },
    { system_key: "adjustment", code: "ADJUSTMENT", name: "Adjustment", kind: "adjustment", category: "adjustment", gl_account_code: "5010" },
    { system_key: "rebate", code: "REBATE", name: "Rebate", kind: "adjustment", category: "discount", gl_account_code: "5030" }
  ].freeze

  LEGACY_CATEGORY_KEYS = {
    "accommodation" => "room_revenue",
    "no_show_charge" => "no_show_revenue",
    "fb" => "fnb_revenue",
    "cash" => "cash_payment",
    "gateway_payment" => "card_payment",
    "booking_payment" => "bank_payment",
    "refund" => "refund",
    "adjustment" => "adjustment",
    "correction" => "adjustment",
    "discount" => "rebate",
    "write_off" => "adjustment",
    "other" => "misc_revenue"
  }.freeze

  def change
    create_table :transaction_codes do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :system_key, null: false
      t.string :code, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.string :category, null: false
      t.boolean :active, default: true, null: false
      t.boolean :system_required, default: false, null: false
      t.string :gl_account_code

      t.timestamps
    end

    add_index :transaction_codes, [ :hotel_id, :system_key ], unique: true
    add_index :transaction_codes, [ :hotel_id, :code ], unique: true
    add_index :transaction_codes, [ :hotel_id, :kind, :category ]

    add_reference :hotel_taxes, :transaction_code, foreign_key: true
    add_reference :folio_transactions, :transaction_code, foreign_key: true

    reversible do |dir|
      dir.up { backfill_transaction_codes }
    end
  end

  private

  def backfill_transaction_codes
    now = Time.current

    MigrationHotel.find_each do |hotel|
      DEFAULT_CODES.each do |attributes|
        MigrationTransactionCode.find_or_create_by!(hotel_id: hotel.id, system_key: attributes[:system_key]) do |code|
          code.assign_attributes(attributes.merge(system_required: true, active: active_for_default_code(hotel, attributes[:system_key]), created_at: now, updated_at: now))
        end
      end

      apply_legacy_gl_codes(hotel)
      backfill_hotel_taxes(hotel, now)
      backfill_folio_transactions(hotel)
    end
  end

  def apply_legacy_gl_codes(hotel)
    return unless table_exists?(:hotel_general_ledger_maps)

    execute(<<~SQL.squish)
      UPDATE transaction_codes
      SET gl_account_code = hotel_general_ledger_maps.gl_code,
          updated_at = CURRENT_TIMESTAMP
      FROM hotel_general_ledger_maps
      WHERE transaction_codes.hotel_id = #{hotel.id}
        AND hotel_general_ledger_maps.hotel_id = #{hotel.id}
        AND transaction_codes.system_key = CASE hotel_general_ledger_maps.transaction_category
          WHEN 'accommodation' THEN 'room_revenue'
          WHEN 'no_show_charge' THEN 'no_show_revenue'
          WHEN 'fb' THEN 'fnb_revenue'
          WHEN 'cash' THEN 'cash_payment'
          WHEN 'gateway_payment' THEN 'card_payment'
          WHEN 'booking_payment' THEN 'bank_payment'
          WHEN 'refund' THEN 'refund'
          WHEN 'adjustment' THEN 'adjustment'
          WHEN 'correction' THEN 'adjustment'
          WHEN 'discount' THEN 'rebate'
          WHEN 'write_off' THEN 'adjustment'
          WHEN 'other' THEN 'misc_revenue'
        END
    SQL
  end

  def backfill_hotel_taxes(hotel, now)
    MigrationHotelTax.where(hotel_id: hotel.id).find_each do |tax|
      code = ensure_custom_tax_code(hotel, tax, now)
      tax.update_columns(transaction_code_id: code.id, updated_at: now)
    end
  end

  def ensure_custom_tax_code(hotel, tax, now)
    MigrationTransactionCode.find_or_create_by!(hotel_id: hotel.id, system_key: "hotel_tax_#{tax.id}") do |code|
      code.assign_attributes(
        code: unique_tax_code(hotel.id, tax.name),
        name: tax.name,
        kind: "tax",
        category: "tax",
        active: tax.enabled,
        system_required: false,
        gl_account_code: tax_gl_account_code(hotel.id),
        created_at: now,
        updated_at: now
      )
    end
  end

  def unique_tax_code(hotel_id, name)
    base = "TAX_#{tax_abbreviation(name)}"
    code = base
    suffix = 2

    while MigrationTransactionCode.exists?(hotel_id: hotel_id, code: code)
      code = "#{base}#{suffix}"
      suffix += 1
    end

    code
  end

  def tax_abbreviation(name)
    words = name.to_s.scan(/[A-Za-z0-9]+/)
    abbreviation = if words.length > 1
      words.map { |word| word[0] }.join
    else
      words.first.to_s[0, 4]
    end

    abbreviation.upcase.presence || "CUSTOM"
  end

  def tax_gl_account_code(hotel_id)
    return "2010" unless table_exists?(:hotel_general_ledger_maps)

    select_value(sanitize_sql([ "SELECT gl_code FROM hotel_general_ledger_maps WHERE hotel_id = ? AND transaction_category = 'tax' LIMIT 1", hotel_id ])).presence || "2010"
  end

  def backfill_folio_transactions(hotel)
    execute(<<~SQL.squish)
      UPDATE folio_transactions
      SET transaction_code_id = transaction_codes.id,
          gl_code = COALESCE(folio_transactions.gl_code, transaction_codes.gl_account_code),
          updated_at = CURRENT_TIMESTAMP
      FROM booking_folios
      JOIN bookings ON bookings.id = booking_folios.booking_id
      JOIN transaction_codes ON transaction_codes.hotel_id = bookings.hotel_id
      WHERE folio_transactions.booking_folio_id = booking_folios.id
        AND bookings.hotel_id = #{hotel.id}
        AND folio_transactions.transaction_code_id IS NULL
        AND transaction_codes.system_key = CASE
          WHEN folio_transactions.category = 'tax' AND folio_transactions.metadata->'tax_line'->>'type' = 'sst' THEN 'sst_tax'
          WHEN folio_transactions.category = 'tax' AND folio_transactions.metadata->'tax_line'->>'type' = 'tourism_tax' THEN 'tourism_tax'
          WHEN folio_transactions.category = 'tax' THEN NULL
          WHEN folio_transactions.category = 'accommodation' THEN 'room_revenue'
          WHEN folio_transactions.category = 'no_show_charge' THEN 'no_show_revenue'
          WHEN folio_transactions.category = 'fb' THEN 'fnb_revenue'
          WHEN folio_transactions.category = 'cash' THEN 'cash_payment'
          WHEN folio_transactions.category = 'gateway_payment' THEN 'card_payment'
          WHEN folio_transactions.category = 'booking_payment' THEN 'bank_payment'
          WHEN folio_transactions.category = 'refund' THEN 'refund'
          WHEN folio_transactions.category IN ('adjustment', 'correction', 'write_off') THEN 'adjustment'
          WHEN folio_transactions.category = 'discount' THEN 'rebate'
          WHEN folio_transactions.category = 'other' THEN 'misc_revenue'
        END
    SQL

    execute(<<~SQL.squish)
      UPDATE folio_transactions
      SET transaction_code_id = hotel_taxes.transaction_code_id,
          gl_code = COALESCE(folio_transactions.gl_code, transaction_codes.gl_account_code),
          updated_at = CURRENT_TIMESTAMP
      FROM booking_folios
      JOIN bookings ON bookings.id = booking_folios.booking_id
      JOIN hotel_taxes ON hotel_taxes.hotel_id = bookings.hotel_id
      JOIN transaction_codes ON transaction_codes.id = hotel_taxes.transaction_code_id
      WHERE folio_transactions.booking_folio_id = booking_folios.id
        AND bookings.hotel_id = #{hotel.id}
        AND folio_transactions.transaction_code_id IS NULL
        AND folio_transactions.category = 'tax'
        AND folio_transactions.metadata->'tax_line'->>'tax_id' = hotel_taxes.id::text
    SQL
  end

  def active_for_default_code(hotel, system_key)
    case system_key
    when "sst_tax"
      hotel.sst_enabled
    when "tourism_tax"
      hotel.tourism_tax_enabled
    else
      true
    end
  end

  def sanitize_sql(statement)
    ActiveRecord::Base.sanitize_sql(statement)
  end
end
