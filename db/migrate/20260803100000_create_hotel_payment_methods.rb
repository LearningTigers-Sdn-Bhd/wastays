# frozen_string_literal: true

class CreateHotelPaymentMethods < ActiveRecord::Migration[8.0]
  class MigrationPaymentMethod < ActiveRecord::Base
    self.table_name = "hotel_payment_methods"
  end

  class MigrationTransactionCode < ActiveRecord::Base
    self.table_name = "transaction_codes"
  end

  SYSTEM_KEYS = %w[cash_payment card_payment bank_payment gateway_manual_recovery_payment ota_collected_payment].freeze

  def change
    create_table :hotel_payment_methods do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true, index: { unique: true }
      t.string :payment_method_type, null: false
      t.boolean :default_cash, null: false, default: false
      t.boolean :guest_advance, null: false, default: false
      t.string :surcharge_posting_type
      t.decimal :surcharge_value, precision: 12, scale: 4
      t.references :surcharge_extra_charge, foreign_key: { to_table: :hotel_extra_charges }
      t.integer :position, null: false, default: 0
      t.timestamps

      t.index %i[hotel_id position]
      t.index :hotel_id, unique: true, where: "default_cash", name: "index_hotel_payment_methods_on_default_cash"
      t.check_constraint "payment_method_type IN ('cash', 'bank_gateway')", name: "hotel_payment_methods_type_allowed"
      t.check_constraint "surcharge_posting_type IS NULL OR surcharge_posting_type IN ('fixed', 'percentage')", name: "hotel_payment_methods_surcharge_type_allowed"
      t.check_constraint "surcharge_value IS NULL OR surcharge_value > 0", name: "hotel_payment_methods_surcharge_value_positive"
      t.check_constraint "surcharge_posting_type <> 'percentage' OR surcharge_value <= 100", name: "hotel_payment_methods_percentage_maximum"
      t.check_constraint <<~SQL.squish, name: "hotel_payment_methods_surcharge_complete"
        (surcharge_posting_type IS NULL AND surcharge_value IS NULL AND surcharge_extra_charge_id IS NULL)
        OR
        (surcharge_posting_type IS NOT NULL AND surcharge_value IS NOT NULL AND surcharge_extra_charge_id IS NOT NULL)
      SQL
    end

    reversible do |direction|
      direction.up { backfill_existing_payment_methods }
    end
  end

  private

  def backfill_existing_payment_methods
    now = Time.current
    positions = Hash.new(0)

    MigrationTransactionCode.where(system_key: SYSTEM_KEYS).order(:hotel_id, :id).find_each do |code|
      positions[code.hotel_id] += 1
      MigrationPaymentMethod.create!(
        hotel_id: code.hotel_id,
        transaction_code_id: code.id,
        payment_method_type: code.system_key == "cash_payment" ? "cash" : "bank_gateway",
        default_cash: code.system_key == "cash_payment",
        guest_advance: code.category == "booking_payment",
        position: positions[code.hotel_id],
        created_at: now,
        updated_at: now
      )
    end
  end
end
