# frozen_string_literal: true

# Two-stage payment terms for standard travel agents: a hotel-level policy, and
# one row per stage on each agent booking, snapshotted when it is created so a
# later change to the policy never rewrites what an agent was promised.
class AddAgentPaymentInstalments < ActiveRecord::Migration[8.1]
  def change
    change_table :hotels, bulk: true do |t|
      t.integer :agent_deposit_percentage, default: 50, null: false
      t.integer :agent_full_payment_days_before_arrival, default: 30, null: false
      t.boolean :agent_deposit_non_refundable, default: false, null: false
    end
    add_check_constraint :hotels, "agent_deposit_percentage BETWEEN 1 AND 100", name: "hotels_agent_deposit_percentage_range"
    add_check_constraint :hotels, "agent_full_payment_days_before_arrival > 0", name: "hotels_agent_full_payment_days_positive"

    create_table :booking_payment_instalments do |t|
      t.references :booking, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.datetime :due_at, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :paid_at
      t.references :paid_by, foreign_key: { to_table: :users }
      t.references :payment_folio_transaction, foreign_key: { to_table: :folio_transactions }, index: { name: "idx_bpi_payment_folio_transaction" }
      t.datetime :refunded_at
      t.references :refunded_by, foreign_key: { to_table: :users }
      t.references :refund_folio_transaction, foreign_key: { to_table: :folio_transactions }, index: { name: "idx_bpi_refund_folio_transaction" }
      t.text :refund_reason
      t.text :note
      t.timestamps
    end
    add_index :booking_payment_instalments, %i[booking_id position], unique: true
    add_check_constraint :booking_payment_instalments, "amount > 0", name: "booking_payment_instalments_amount_positive"
    add_check_constraint :booking_payment_instalments, "kind IN ('deposit', 'balance', 'full')", name: "booking_payment_instalments_kind_allowed"
    add_check_constraint :booking_payment_instalments, "status IN ('pending', 'paid', 'refunded', 'waived')", name: "booking_payment_instalments_status_allowed"
  end
end
