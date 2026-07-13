# frozen_string_literal: true

class AddDisplayFieldsToGuestRegistrationCards < ActiveRecord::Migration[7.1]
  def change
    add_column :hotels, :guest_registration_card_fields, :jsonb
    add_column :guest_registration_cards, :display_fields_snapshot, :jsonb
  end
end
