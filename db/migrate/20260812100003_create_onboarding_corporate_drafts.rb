# frozen_string_literal: true

class CreateOnboardingCorporateDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :onboarding_corporate_drafts do |t|
      t.references :hotel, null: false, foreign_key: true
      # Set when submission turns the draft into a real invitation. Its presence
      # is what makes delivery idempotent across a retried submission.
      t.references :invitation, null: true, foreign_key: true
      t.string :email, null: false
      t.string :company_name
      t.string :account_type, null: false, default: "company"
      t.string :relationship_type, null: false, default: "standard"
      t.decimal :credit_limit, precision: 12, scale: 2
      t.string :credit_currency, null: false
      t.integer :payment_terms_days
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :onboarding_corporate_drafts,
              "hotel_id, LOWER(email)",
              unique: true,
              name: "index_onboarding_corporate_drafts_on_hotel_and_lower_email"

    # One draft can produce at most one invitation, even if two submissions race.
    add_index :onboarding_corporate_drafts, :invitation_id,
              unique: true,
              where: "invitation_id IS NOT NULL",
              name: "index_onboarding_corporate_drafts_on_delivered_invitation"
  end
end
