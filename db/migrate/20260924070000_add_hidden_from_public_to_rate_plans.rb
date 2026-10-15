# frozen_string_literal: true

# Lets a property keep a plan (typically Standard) off the public booking
# site's room search while still selling it through front desk and, where
# ta_access allows, the travel agent portal -- a hidden pricing anchor rather
# than an offer guests pick directly.
class AddHiddenFromPublicToRatePlans < ActiveRecord::Migration[8.1]
  def change
    add_column :rate_plans, :hidden_from_public, :boolean, default: false, null: false
  end
end
