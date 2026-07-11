# frozen_string_literal: true

class CreateBillingRouteBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_route_batches do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :idempotency_key, null: false
      t.datetime :completed_at
      t.timestamps
    end
    add_index :billing_route_batches, [ :booking_id, :idempotency_key ], unique: true,
      name: "idx_billing_route_batches_idempotency"
  end
end
