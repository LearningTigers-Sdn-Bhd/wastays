# frozen_string_literal: true

class AddPublicTokenToGuestRegistrationCards < ActiveRecord::Migration[8.1]
  def change
    add_column :guest_registration_cards, :public_token, :string
    add_index :guest_registration_cards, :public_token, unique: true
  end
end
