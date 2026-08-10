# frozen_string_literal: true

class CreateChannelSettlementFoundation < ActiveRecord::Migration[8.0]
  def up
    add_reference :booking_billing_parties, :booking_source,
      null: true,
      foreign_key: true,
      index: true

    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_kind_allowed"
    add_check_constraint :booking_billing_parties,
      "party_kind IN ('guest', 'company', 'ota')",
      name: "booking_billing_parties_kind_allowed"

    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_one_identity"
    add_check_constraint :booking_billing_parties,
      "((booking_guest_id IS NOT NULL)::integer + (hotel_corporate_account_id IS NOT NULL)::integer + (booking_source_id IS NOT NULL)::integer) = 1",
      name: "booking_billing_parties_one_identity"

    add_index :booking_billing_parties,
      [ :booking_id, :booking_source_id ],
      unique: true,
      where: "booking_source_id IS NOT NULL",
      name: "idx_booking_billing_parties_unique_ota"
    add_check_constraint :booking_billing_parties,
      "(party_kind = 'guest' AND booking_guest_id IS NOT NULL AND hotel_corporate_account_id IS NULL AND booking_source_id IS NULL) OR (party_kind = 'company' AND booking_guest_id IS NULL AND hotel_corporate_account_id IS NOT NULL AND booking_source_id IS NULL) OR (party_kind = 'ota' AND booking_guest_id IS NULL AND hotel_corporate_account_id IS NULL AND booking_source_id IS NOT NULL)",
      name: "booking_billing_parties_identity_matches_kind"

    remove_check_constraint :booking_folios, name: "booking_folios_payer_type_allowed"
    add_check_constraint :booking_folios,
      "payer_type IN ('guest', 'company', 'ota', 'agent', 'hotel', 'custom')",
      name: "booking_folios_payer_type_allowed"

    create_table :channel_settlements do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_source, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :channel_manager_reference, null: false
      t.string :latest_revision_id
      t.string :collection_by, null: false, default: "unknown"
      t.string :settlement_method, null: false, default: "unknown"
      t.string :status, null: false, default: "unknown"
      t.string :currency, null: false
      t.decimal :gross_amount, precision: 12, scale: 2, null: false
      t.decimal :commission_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :expected_net_amount, precision: 12, scale: 2, null: false
      t.boolean :virtual_card_is_virtual
      t.string :virtual_card_currency
      t.decimal :virtual_card_available_balance, precision: 12, scale: 2
      t.date :virtual_card_effective_date
      t.date :virtual_card_expiration_date
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :channel_settlements,
      [ :hotel_id, :provider, :channel_manager_reference ],
      unique: true,
      name: "idx_channel_settlements_identity"
    add_index :channel_settlements, [ :hotel_id, :status ]
    add_index :channel_settlements, [ :booking_source_id, :status ]
    add_check_constraint :channel_settlements,
      "collection_by IN ('property', 'ota', 'unknown')",
      name: "channel_settlements_collection_by_allowed"
    add_check_constraint :channel_settlements,
      "settlement_method IN ('guest_card', 'virtual_card', 'bank_transfer', 'unknown')",
      name: "channel_settlements_method_allowed"
    add_check_constraint :channel_settlements,
      "status IN ('property_collection_required', 'awaiting_ota_settlement', 'virtual_card_not_ready', 'ready_to_charge', 'partially_received', 'received', 'underpaid', 'overpaid', 'failed', 'cancelled', 'unknown')",
      name: "channel_settlements_status_allowed"
    add_check_constraint :channel_settlements, "gross_amount >= 0", name: "channel_settlements_gross_amount_nonnegative"
    add_check_constraint :channel_settlements, "commission_amount >= 0", name: "channel_settlements_commission_amount_nonnegative"
    add_check_constraint :channel_settlements, "commission_amount <= gross_amount", name: "channel_settlements_commission_not_over_gross"
    add_check_constraint :channel_settlements, "expected_net_amount >= 0", name: "channel_settlements_expected_net_amount_nonnegative"
    add_check_constraint :channel_settlements,
      "expected_net_amount = gross_amount - commission_amount",
      name: "channel_settlements_expected_net_amount_matches"
    add_check_constraint :channel_settlements,
      "virtual_card_available_balance IS NULL OR virtual_card_available_balance >= 0",
      name: "channel_settlements_virtual_card_balance_nonnegative"

    create_table :channel_settlement_allocations do |t|
      t.references :channel_settlement, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true
      t.string :currency, null: false
      t.decimal :gross_amount, precision: 12, scale: 2, null: false
      t.decimal :commission_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :expected_net_amount, precision: 12, scale: 2, null: false

      t.timestamps
    end

    add_index :channel_settlement_allocations,
      [ :channel_settlement_id, :booking_id ],
      unique: true,
      name: "idx_channel_settlement_allocations_settlement_booking"
    add_index :channel_settlement_allocations, [ :booking_id, :booking_folio_id ]
    add_check_constraint :channel_settlement_allocations, "gross_amount >= 0", name: "channel_settlement_allocations_gross_amount_nonnegative"
    add_check_constraint :channel_settlement_allocations, "commission_amount >= 0", name: "channel_settlement_allocations_commission_amount_nonnegative"
    add_check_constraint :channel_settlement_allocations, "commission_amount <= gross_amount", name: "channel_settlement_allocations_commission_not_over_gross"
    add_check_constraint :channel_settlement_allocations, "expected_net_amount >= 0", name: "channel_settlement_allocations_expected_net_amount_nonnegative"
    add_check_constraint :channel_settlement_allocations,
      "expected_net_amount = gross_amount - commission_amount",
      name: "channel_settlement_allocations_expected_net_amount_matches"

    create_table :channel_settlement_receipts do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_source, null: false, foreign_key: true
      t.references :hotel_payment_method, null: false, foreign_key: true
      t.string :settlement_method, null: false, default: "unknown"
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false
      t.datetime :received_at, null: false
      t.string :external_reference
      t.text :notes
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :channel_settlement_receipts, [ :hotel_id, :received_at ]
    add_index :channel_settlement_receipts, [ :booking_source_id, :received_at ]
    add_index :channel_settlement_receipts,
      [ :hotel_id, :external_reference ],
      unique: true,
      where: "external_reference IS NOT NULL",
      name: "idx_channel_settlement_receipts_external_reference"
    add_check_constraint :channel_settlement_receipts,
      "settlement_method IN ('guest_card', 'virtual_card', 'bank_transfer', 'unknown')",
      name: "channel_settlement_receipts_method_allowed"
    add_check_constraint :channel_settlement_receipts, "amount > 0", name: "channel_settlement_receipts_amount_positive"

    create_table :channel_settlement_receipt_allocations do |t|
      t.references :channel_settlement_receipt, null: false, foreign_key: true
      t.references :channel_settlement_allocation, null: false, foreign_key: true
      t.string :currency, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false

      t.timestamps
    end

    add_index :channel_settlement_receipt_allocations,
      [ :channel_settlement_receipt_id, :channel_settlement_allocation_id ],
      unique: true,
      name: "idx_channel_settlement_receipt_allocations_unique"
    add_check_constraint :channel_settlement_receipt_allocations,
      "amount > 0",
      name: "channel_settlement_receipt_allocations_amount_positive"
  end

  def down
    drop_table :channel_settlement_receipt_allocations
    drop_table :channel_settlement_receipts
    drop_table :channel_settlement_allocations
    drop_table :channel_settlements

    remove_check_constraint :booking_folios, name: "booking_folios_payer_type_allowed"
    add_check_constraint :booking_folios,
      "payer_type IN ('guest', 'company', 'agent', 'hotel', 'custom')",
      name: "booking_folios_payer_type_allowed"

    remove_index :booking_billing_parties, name: "idx_booking_billing_parties_unique_ota"
    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_identity_matches_kind"
    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_one_identity"
    add_check_constraint :booking_billing_parties,
      "((booking_guest_id IS NOT NULL)::integer + (hotel_corporate_account_id IS NOT NULL)::integer) = 1",
      name: "booking_billing_parties_one_identity"
    remove_check_constraint :booking_billing_parties, name: "booking_billing_parties_kind_allowed"
    add_check_constraint :booking_billing_parties,
      "party_kind IN ('guest', 'company')",
      name: "booking_billing_parties_kind_allowed"
    remove_reference :booking_billing_parties, :booking_source, foreign_key: true, index: true
  end
end
