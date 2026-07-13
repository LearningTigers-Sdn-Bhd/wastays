# frozen_string_literal: true

class CreateGroupDeposits < ActiveRecord::Migration[8.0]
  def change
    create_table :group_deposits do |t|
      t.references :group_booking, null: false, foreign_key: true
      t.references :hotel, null: false, foreign_key: true
      t.references :hotel_corporate_account, null: true, foreign_key: true
      t.references :received_by, null: true, foreign_key: { to_table: :users }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false
      t.string :payment_method, null: false
      t.string :external_reference
      t.string :status, null: false, default: "received"
      t.datetime :received_at, null: false
      t.datetime :refunded_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :group_deposits, [ :hotel_id, :external_reference ], unique: true, where: "external_reference IS NOT NULL"
    add_check_constraint :group_deposits, "amount > 0", name: "group_deposits_amount_positive"
    add_check_constraint :group_deposits,
      "status IN ('received', 'partially_allocated', 'allocated', 'partially_refunded', 'refunded', 'cancelled')",
      name: "group_deposits_status_allowed"

    create_table :group_deposit_allocations do |t|
      t.references :group_deposit, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true
      t.references :folio_transaction, null: true, foreign_key: true
      t.references :allocated_by, null: true, foreign_key: { to_table: :users }
      t.references :reversal_of, null: true, foreign_key: { to_table: :group_deposit_allocations }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :status, null: false, default: "active"
      t.datetime :allocated_at, null: false
      t.datetime :reversed_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :group_deposit_allocations,
      :reversal_of_id,
      unique: true,
      where: "reversal_of_id IS NOT NULL",
      name: "idx_group_deposit_allocations_one_reversal"
    add_check_constraint :group_deposit_allocations, "amount > 0", name: "group_deposit_allocations_amount_positive"
    add_check_constraint :group_deposit_allocations,
      "status IN ('active', 'reversed')",
      name: "group_deposit_allocations_status_allowed"
  end
end
