# frozen_string_literal: true

class CreateOnboardingDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_deliveries do |t|
      t.references :onboarding_submission, null: false, foreign_key: true
      t.string :delivery_type, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending"
      t.string :recipient_email
      t.string :source_type
      t.bigint :source_id
      t.integer :attempt_count, null: false, default: 0
      t.text :error_message
      t.datetime :attempted_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :onboarding_deliveries, :idempotency_key, unique: true
    add_index :onboarding_deliveries, [ :status, :updated_at ]
    add_index :onboarding_deliveries, [ :source_type, :source_id ]
    add_check_constraint :onboarding_deliveries,
                         "delivery_type IN ('staff_invitation', 'corporate_invitation', 'admin_submitted', 'owner_changes_requested', 'owner_approved')",
                         name: "onboarding_deliveries_type_allowed"
    add_check_constraint :onboarding_deliveries,
                         "status IN ('pending', 'processing', 'sent', 'held', 'failed')",
                         name: "onboarding_deliveries_status_allowed"
  end
end
