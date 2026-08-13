# frozen_string_literal: true

class CreateOnboardingStaffDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :onboarding_staff_drafts do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.string :name
      t.string :email, null: false

      t.timestamps
    end

    add_index :onboarding_staff_drafts,
              "hotel_id, LOWER(email)",
              unique: true,
              name: "index_onboarding_staff_drafts_on_hotel_and_lower_email"
  end
end
