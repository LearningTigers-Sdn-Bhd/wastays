# frozen_string_literal: true

class CreateGroupBillingDomain < ActiveRecord::Migration[8.0]
  def change
    create_table :group_billing_arrangements do |t|
      t.references :group_booking, null: false, foreign_key: true
      t.references :hotel, null: false, foreign_key: true
      t.references :hotel_corporate_account, null: true, foreign_key: true
      t.string :name, null: false
      t.string :payer_type, null: false, default: "guest"
      t.string :settlement_type, null: false, default: "cash_bank"
      t.string :preferred_payment_method
      t.string :billing_reference
      t.string :purchase_order_reference
      t.string :authorization_reference
      t.date :valid_from
      t.date :valid_until
      t.string :status, null: false, default: "active"
      t.jsonb :coverage, null: false, default: {}
      t.timestamps
    end

    add_index :group_billing_arrangements, [ :group_booking_id, :status ]
    add_check_constraint :group_billing_arrangements,
      "payer_type IN ('guest', 'company')",
      name: "group_billing_arrangements_payer_allowed"
    add_check_constraint :group_billing_arrangements,
      "settlement_type IN ('cash_bank', 'city_ledger')",
      name: "group_billing_arrangements_settlement_allowed"
    add_check_constraint :group_billing_arrangements,
      "status IN ('active', 'inactive')",
      name: "group_billing_arrangements_status_allowed"

    create_table :booking_billing_assignments do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :group_billing_arrangement, null: false, foreign_key: true
      t.string :charge_category, null: false
      t.boolean :local_exception, null: false, default: false
      t.date :effective_from
      t.date :effective_until
      t.jsonb :coverage, null: false, default: {}
      t.timestamps
    end

    add_index :booking_billing_assignments,
      [ :booking_id, :charge_category ],
      unique: true,
      name: "idx_booking_billing_assignment_category"
  end
end
