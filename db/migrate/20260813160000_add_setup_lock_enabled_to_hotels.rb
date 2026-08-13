# frozen_string_literal: true

# Per-hotel opt-in for the setup lock, which keeps a property that has not been
# submitted yet inside onboarding rather than loose in the hotel portal.
#
# Defaults to off so deploying changes nothing. Enable it hotel by hotel from the
# admin onboarding page.
class AddSetupLockEnabledToHotels < ActiveRecord::Migration[8.1]
  def change
    add_column :hotels, :setup_lock_enabled, :boolean, default: false, null: false
  end
end
