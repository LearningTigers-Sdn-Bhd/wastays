# frozen_string_literal: true

class CreateBookingTaxInclusionOverrides < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_tax_inclusion_overrides do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true
      t.references :hotel_tax, null: true, foreign_key: true
      t.string :primary_tax_key
      t.string :action, null: false
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :reason
      t.timestamps
    end

    add_check_constraint :booking_tax_inclusion_overrides,
      "((hotel_tax_id IS NOT NULL)::integer + (primary_tax_key IS NOT NULL)::integer) = 1",
      name: "booking_tax_overrides_one_tax_source"
    add_check_constraint :booking_tax_inclusion_overrides, "action IN ('include', 'exclude')",
      name: "booking_tax_overrides_action_allowed"
    add_index :booking_tax_inclusion_overrides, [ :booking_id, :transaction_code_id, :primary_tax_key ],
      unique: true, where: "primary_tax_key IS NOT NULL", name: "idx_booking_tax_overrides_primary"
    add_index :booking_tax_inclusion_overrides, [ :booking_id, :transaction_code_id, :hotel_tax_id ],
      unique: true, where: "hotel_tax_id IS NOT NULL", name: "idx_booking_tax_overrides_hotel_tax"
  end
end
