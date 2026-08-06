# frozen_string_literal: true

class CreateGuestRegistrationCards < ActiveRecord::Migration[7.1]
  def change
    create_table :guest_registration_cards do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "draft"
      t.string :signer_name
      t.text :signature_data_url
      t.jsonb :terms_snapshot, null: false, default: {}
      t.datetime :signed_at

      t.timestamps
    end

    add_check_constraint :guest_registration_cards, "status IN ('draft', 'signed')", name: "guest_registration_cards_status_allowed"
  end
end
