# frozen_string_literal: true

class AddGuestRegistrationCardShowPricingToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :guest_registration_card_show_pricing, :boolean, default: true, null: false
  end
end
