# frozen_string_literal: true

class CreateOtaFinancialMappingAndVariancePolicy < ActiveRecord::Migration[8.0]
  def change
    create_table :ota_financial_component_mappings do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_source, null: true, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.string :provider, null: false
      t.string :component_kind, null: false
      t.string :normalized_provider_type, null: false, default: ""
      t.string :normalized_provider_name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :ota_financial_component_mappings,
      %i[hotel_id provider component_kind normalized_provider_type normalized_provider_name],
      unique: true,
      where: "booking_source_id IS NULL",
      name: "idx_ota_component_mappings_provider_default"
    add_index :ota_financial_component_mappings,
      %i[hotel_id provider booking_source_id component_kind normalized_provider_type normalized_provider_name],
      unique: true,
      where: "booking_source_id IS NOT NULL",
      name: "idx_ota_component_mappings_source_override"
    add_index :ota_financial_component_mappings, %i[hotel_id active]
    add_check_constraint :ota_financial_component_mappings,
      "component_kind IN ('fee', 'service', 'tax', 'discount')",
      name: "ota_component_mappings_kind_allowed"

    create_table :ota_rate_variance_policies do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }
      t.string :mode, null: false, default: "recommended"
      t.decimal :maximum_percentage, precision: 8, scale: 4, null: false, default: 1
      t.decimal :maximum_amount_per_room_night, precision: 15, scale: 2, null: false, default: 10
      t.string :currency, null: false

      t.timestamps
    end

    add_check_constraint :ota_rate_variance_policies,
      "mode IN ('recommended', 'strict', 'custom')",
      name: "ota_rate_variance_policies_mode_allowed"
    add_check_constraint :ota_rate_variance_policies,
      "maximum_percentage IS NULL OR maximum_percentage >= 0",
      name: "ota_rate_variance_policies_percentage_nonnegative"
    add_check_constraint :ota_rate_variance_policies,
      "maximum_amount_per_room_night IS NULL OR maximum_amount_per_room_night >= 0",
      name: "ota_rate_variance_policies_amount_nonnegative"
    add_check_constraint :ota_rate_variance_policies,
      "maximum_percentage IS NOT NULL AND maximum_amount_per_room_night IS NOT NULL",
      name: "ota_rate_variance_policies_thresholds_present"
  end
end
