# frozen_string_literal: true

class CreateGroupBillingChangeBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :group_billing_change_batches do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :group_booking, null: false, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :idempotency_key, null: false
      t.string :payload_digest, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at
      t.timestamps
    end

    add_index :group_billing_change_batches, [ :group_booking_id, :idempotency_key ],
      unique: true, name: "idx_group_billing_change_batches_idempotency"
    add_check_constraint :group_billing_change_batches,
      "status IN ('pending', 'completed')", name: "group_billing_change_batches_status_allowed"
  end
end
