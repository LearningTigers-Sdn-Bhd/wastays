# frozen_string_literal: true

class CreateHotelOnboardingFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :hotel_onboarding_sections do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :section_key, null: false
      t.string :state, null: false, default: "not_started"
      t.datetime :completed_at
      t.datetime :skipped_at
      t.jsonb :decision_metadata, null: false, default: {}
      t.timestamps

      t.index [ :hotel_id, :section_key ], unique: true
      t.index [ :hotel_id, :state ]
      t.check_constraint "state IN ('not_started', 'in_progress', 'complete', 'skipped', 'needs_attention')",
                         name: "hotel_onboarding_sections_state_allowed"
    end

    create_table :onboarding_audit_events do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :section_key
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps

      t.index [ :hotel_id, :occurred_at ]
      t.index [ :hotel_id, :section_key, :occurred_at ], name: "idx_onboarding_events_section_time"
    end
  end
end
