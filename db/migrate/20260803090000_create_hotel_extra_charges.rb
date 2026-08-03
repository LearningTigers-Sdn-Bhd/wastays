# frozen_string_literal: true

class CreateHotelExtraCharges < ActiveRecord::Migration[8.0]
  EXTRA_CHARGE_SYSTEM_KEYS = %w[
    fnb_revenue
    parking_revenue
    damage_revenue
    cleaning_revenue
    misc_revenue
  ].freeze

  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  class MigrationHotelTax < ActiveRecord::Base
    self.table_name = "hotel_taxes"
  end

  class MigrationFolioTransaction < ActiveRecord::Base
    self.table_name = "folio_transactions"
  end

  class MigrationExtraCharge < ActiveRecord::Base
    self.table_name = "hotel_extra_charges"
  end

  def up
    create_table :hotel_extra_charges do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true, index: { unique: true }
      t.text :description
      t.string :pricing_type, null: false, default: "manual"
      t.decimal :rate_value, precision: 12, scale: 4
      t.string :charging_unit, null: false, default: "per_item"
      t.string :percentage_basis
      t.boolean :allow_amount_override, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :hotel_extra_charges, [ :hotel_id, :position ]
    add_check_constraint :hotel_extra_charges,
      "pricing_type IN ('manual', 'fixed', 'percentage')",
      name: "hotel_extra_charges_pricing_type_allowed"
    add_check_constraint :hotel_extra_charges,
      "charging_unit IN ('per_item', 'per_stay', 'per_night', 'per_room', 'per_room_night', 'per_person', 'per_person_night')",
      name: "hotel_extra_charges_charging_unit_allowed"
    add_check_constraint :hotel_extra_charges,
      "percentage_basis IS NULL OR percentage_basis IN ('room_charges', 'non_tax_charges')",
      name: "hotel_extra_charges_percentage_basis_allowed"
    add_check_constraint :hotel_extra_charges,
      "rate_value IS NULL OR rate_value > 0",
      name: "hotel_extra_charges_rate_value_positive"

    add_column :folio_transactions, :transaction_code_code_snapshot, :string
    add_column :folio_transactions, :transaction_code_name_snapshot, :string

    backfill_transaction_snapshots
    backfill_extra_charges
  end

  def down
    remove_column :folio_transactions, :transaction_code_name_snapshot
    remove_column :folio_transactions, :transaction_code_code_snapshot
    drop_table :hotel_extra_charges
  end

  private

  def backfill_transaction_snapshots
    execute <<~SQL.squish
      UPDATE folio_transactions
      SET transaction_code_code_snapshot = transaction_codes.code,
          transaction_code_name_snapshot = transaction_codes.name
      FROM transaction_codes
      WHERE folio_transactions.transaction_code_id = transaction_codes.id
    SQL
  end

  def backfill_extra_charges
    tax_code_ids = MigrationHotelTax.where.not(transaction_code_id: nil).select(:transaction_code_id)
    eligible = MigrationTransactionCode.where(kind: "charge")
      .where.not(id: tax_code_ids)
      .where(
        "system_key IN (:system_keys) OR system_required = FALSE",
        system_keys: EXTRA_CHARGE_SYSTEM_KEYS
      )
      .order(:hotel_id, :id)

    now = Time.current
    eligible.find_each do |transaction_code|
      shorten_code!(transaction_code) if transaction_code.code.length > 10
      MigrationExtraCharge.create!(
        hotel_id: transaction_code.hotel_id,
        transaction_code_id: transaction_code.id,
        pricing_type: "manual",
        charging_unit: "per_item",
        allow_amount_override: true,
        position: next_position(transaction_code.hotel_id),
        created_at: now,
        updated_at: now
      )
    end
  end

  def shorten_code!(transaction_code)
    base = transaction_code.code.to_s.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_")
    base = "CHARGE" if base.blank?
    candidate = base.first(10)
    suffix = 2

    while MigrationTransactionCode.where(hotel_id: transaction_code.hotel_id, code: candidate).where.not(id: transaction_code.id).exists?
      suffix_text = suffix.to_s
      candidate = "#{base.first(10 - suffix_text.length)}#{suffix_text}"
      suffix += 1
    end

    transaction_code.update_columns(code: candidate, updated_at: Time.current)
  end

  def next_position(hotel_id)
    MigrationExtraCharge.where(hotel_id: hotel_id).maximum(:position).to_i + 1
  end
end
