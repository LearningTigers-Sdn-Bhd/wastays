# frozen_string_literal: true

class CreateHotelOtaCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :hotel_ota_credentials do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :channel_name, null: false
      t.string :property_code
      # Encrypted at rest, so the column has to hold the ciphertext envelope
      # rather than the length of what was typed.
      t.text :username
      t.text :password
      t.string :market_manager_name
      t.string :market_manager_phone
      t.string :market_manager_email
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    # One row per channel for a property: the owner is describing the extranets
    # this hotel has, and a second Booking.com row is a duplicate rather than a
    # second account.
    add_index :hotel_ota_credentials, "hotel_id, lower(channel_name)",
              unique: true, name: "index_hotel_ota_credentials_on_hotel_and_lower_channel"
  end
end
