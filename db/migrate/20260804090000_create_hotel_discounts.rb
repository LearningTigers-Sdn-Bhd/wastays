# frozen_string_literal: true

class CreateHotelDiscounts < ActiveRecord::Migration[8.0]
  class MigrationDiscount < ActiveRecord::Base
    self.table_name = "hotel_discounts"
  end

  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  def up
    create_table :hotel_discounts do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true, index: { unique: true }
      t.text :description
      t.string :pricing_type, null: false, default: "manual"
      t.decimal :rate_value, precision: 12, scale: 4
      t.string :application_scope, null: false, default: "all_eligible_charges"
      t.boolean :allow_amount_override, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :hotel_discount_transaction_codes do |t|
      t.references :hotel_discount, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true
      t.timestamps
      t.index %i[hotel_discount_id transaction_code_id], unique: true, name: "index_discount_codes_on_discount_and_code"
    end

    add_index :hotel_discounts, %i[hotel_id position]
    add_check_constraint :hotel_discounts, "pricing_type IN ('manual', 'fixed', 'percentage')", name: "hotel_discounts_pricing_type_allowed"
    add_check_constraint :hotel_discounts, "application_scope IN ('room_charges', 'all_eligible_charges', 'selected_charges')", name: "hotel_discounts_scope_allowed"
    add_check_constraint :hotel_discounts, "rate_value IS NULL OR rate_value > 0", name: "hotel_discounts_rate_value_positive"
    add_check_constraint :hotel_discounts, "pricing_type <> 'percentage' OR rate_value <= 100", name: "hotel_discounts_percentage_maximum"

    backfill_discounts
  end

  def down
    drop_table :hotel_discount_transaction_codes
    drop_table :hotel_discounts
  end

  private

  def backfill_discounts
    positions = Hash.new(0)
    now = Time.current
    MigrationTransactionCode.where(kind: "adjustment", category: "discount").order(:hotel_id, :id).find_each do |code|
      positions[code.hotel_id] += 1
      MigrationDiscount.create!(
        hotel_id: code.hotel_id,
        transaction_code_id: code.id,
        pricing_type: "manual",
        application_scope: "all_eligible_charges",
        allow_amount_override: true,
        position: positions[code.hotel_id],
        created_at: now,
        updated_at: now
      )
    end
  end
end
