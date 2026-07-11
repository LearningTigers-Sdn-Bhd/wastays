# frozen_string_literal: true

class AddBlacklistedToGuests < ActiveRecord::Migration[7.2]
  def change
    add_column :guests, :blacklisted, :boolean, default: false, null: false
    add_index :guests, :blacklisted
  end
end
