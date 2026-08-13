# frozen_string_literal: true

class CreateOtaFinancialSnapshotsAndComponents < ActiveRecord::Migration[8.0]
  def change
    create_table :ota_financial_snapshots do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_source, null: true, foreign_key: true
      t.references :booking, null: true, foreign_key: true
      t.references :group_booking, null: true, foreign_key: true
      t.string :provider, null: false
      t.string :channel_manager_reference, null: false
      t.string :provider_revision_id, null: false
      t.bigint :provider_revision_number
      t.string :original_currency, null: false
      t.decimal :original_gross_amount, precision: 15, scale: 4, null: false
      t.string :currency, null: false
      t.decimal :gross_amount, precision: 15, scale: 2, null: false
      t.decimal :original_accommodation_amount, precision: 15, scale: 4, null: false, default: 0
      t.decimal :accommodation_amount, precision: 15, scale: 2, null: false, default: 0
      t.decimal :expected_pms_accommodation_amount, precision: 15, scale: 2
      t.decimal :variance_amount, precision: 15, scale: 2
      t.decimal :variance_percentage, precision: 12, scale: 6
      t.string :variance_reason
      t.decimal :exchange_rate, precision: 20, scale: 10, null: false, default: 1
      t.string :exchange_rate_source, null: false
      t.decimal :conversion_rounding_amount, precision: 15, scale: 2, null: false, default: 0
      t.string :reconciliation_status, null: false
      t.decimal :mismatch_amount, precision: 15, scale: 2, null: false, default: 0
      t.jsonb :policy_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :current, null: false, default: true
      t.datetime :superseded_at

      t.timestamps
    end

    add_index :ota_financial_snapshots,
      %i[hotel_id provider channel_manager_reference provider_revision_id],
      unique: true,
      name: "idx_ota_snapshots_provider_revision"
    add_index :ota_financial_snapshots, :booking_id,
      unique: true,
      where: "booking_id IS NOT NULL AND current = TRUE",
      name: "idx_ota_snapshots_current_booking"
    add_index :ota_financial_snapshots, :group_booking_id,
      unique: true,
      where: "group_booking_id IS NOT NULL AND current = TRUE",
      name: "idx_ota_snapshots_current_group_booking"
    add_index :ota_financial_snapshots, %i[hotel_id reconciliation_status current],
      name: "idx_ota_snapshots_hotel_reconciliation"

    add_check_constraint :ota_financial_snapshots,
      "(booking_id IS NOT NULL) <> (group_booking_id IS NOT NULL)",
      name: "ota_snapshots_exactly_one_target"
    add_check_constraint :ota_financial_snapshots,
      "provider = lower(provider)",
      name: "ota_snapshots_provider_normalized"
    add_check_constraint :ota_financial_snapshots,
      "variance_reason IS NULL OR variance_reason IN ('fx_round_trip', 'occupancy_difference', 'channel_adjustment', 'promotion', 'unexplained')",
      name: "ota_snapshots_variance_reason_allowed"
    add_check_constraint :ota_financial_snapshots,
      "reconciliation_status IN ('balanced', 'balanced_with_rounding', 'accepted_fx_variance', 'unmapped_components', 'total_mismatch', 'rate_review_required')",
      name: "ota_snapshots_reconciliation_allowed"
    add_check_constraint :ota_financial_snapshots,
      "original_gross_amount >= 0 AND gross_amount >= 0 AND original_accommodation_amount >= 0 AND accommodation_amount >= 0 AND (expected_pms_accommodation_amount IS NULL OR expected_pms_accommodation_amount >= 0)",
      name: "ota_snapshots_totals_nonnegative"
    add_check_constraint :ota_financial_snapshots,
      "exchange_rate > 0",
      name: "ota_snapshots_exchange_rate_positive"

    create_table :ota_financial_components do |t|
      t.references :ota_financial_snapshot, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :booking_room, null: true, foreign_key: true
      t.references :transaction_code, null: false, foreign_key: true
      t.string :component_kind, null: false
      t.string :stable_key, null: false
      t.date :stay_date, null: false
      t.string :provider_name, null: false
      t.string :provider_type
      t.string :normalized_provider_name, null: false
      t.string :normalized_provider_type, null: false, default: ""
      t.string :original_currency, null: false
      t.decimal :original_amount, precision: 15, scale: 4, null: false
      t.string :currency, null: false
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.decimal :gross_effect_amount, precision: 15, scale: 2, null: false
      t.decimal :posting_amount, precision: 15, scale: 2, null: false
      t.boolean :is_inclusive, null: false, default: false
      t.string :rate_type
      t.decimal :rate, precision: 15, scale: 6
      t.string :basis
      t.decimal :basis_amount, precision: 15, scale: 4
      t.string :mapping_status, null: false
      t.decimal :allocation_rounding_amount, precision: 15, scale: 2, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ota_financial_components,
      %i[ota_financial_snapshot_id booking_id stable_key],
      unique: true,
      name: "idx_ota_components_snapshot_booking_stable_key"
    add_index :ota_financial_components, %i[booking_id stay_date],
      name: "idx_ota_components_booking_stay_date"
    add_index :ota_financial_components, %i[mapping_status component_kind],
      name: "idx_ota_components_mapping_kind"

    add_check_constraint :ota_financial_components,
      "component_kind IN ('accommodation', 'fee', 'service', 'tax', 'discount')",
      name: "ota_components_kind_allowed"
    add_check_constraint :ota_financial_components,
      "mapping_status IN ('mapped', 'canonical', 'unmapped')",
      name: "ota_components_mapping_status_allowed"
    add_check_constraint :ota_financial_components,
      "rate_type IS NULL OR rate_type IN ('percentage', 'flat')",
      name: "ota_components_rate_type_allowed"
    add_check_constraint :ota_financial_components,
      "component_kind <> 'accommodation' OR booking_room_id IS NOT NULL",
      name: "ota_components_accommodation_has_room"
    add_check_constraint :ota_financial_components,
      "original_amount >= 0 AND amount >= 0",
      name: "ota_components_amounts_nonnegative"
  end
end
