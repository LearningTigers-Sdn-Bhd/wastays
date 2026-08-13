# frozen_string_literal: true

class CreateOnboardingSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_submissions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending_review"
      t.integer :snapshot_version, null: false, default: 1
      t.jsonb :snapshot, null: false, default: {}
      t.jsonb :readiness_snapshot, null: false, default: {}
      t.string :configuration_digest, null: false
      t.text :review_explanation
      t.datetime :submitted_at, null: false
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :onboarding_submissions, :idempotency_key, unique: true
    add_index :onboarding_submissions, [ :hotel_id, :submitted_at ]
    add_index :onboarding_submissions, :hotel_id, unique: true,
              where: "status = 'pending_review'", name: "idx_onboarding_submissions_one_pending"
    add_check_constraint :onboarding_submissions,
                         "status IN ('pending_review', 'changes_requested', 'approved')",
                         name: "onboarding_submissions_status_allowed"
  end
end
