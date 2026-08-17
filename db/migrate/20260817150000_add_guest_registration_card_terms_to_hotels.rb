# frozen_string_literal: true

class AddGuestRegistrationCardTermsToHotels < ActiveRecord::Migration[8.1]
  def change
    add_column :hotels, :guest_registration_card_terms, :text
  end
end
