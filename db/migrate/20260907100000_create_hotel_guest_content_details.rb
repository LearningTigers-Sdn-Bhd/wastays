# frozen_string_literal: true

class CreateHotelGuestContentDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_amenity_details do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :amenity, null: false, foreign_key: true
      t.string :location
      t.text :opening_hours
      t.text :fee_information
      t.boolean :reservation_required, null: false, default: false
      t.text :reservation_instructions
      t.text :guest_notes
      t.timestamps
    end
    add_index :hotel_amenity_details, %i[hotel_id amenity_id], unique: true

    create_table :hotel_wifi_networks do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :label, null: false
      t.string :ssid, null: false
      t.text :password
      t.string :security_type, null: false, default: "protected"
      t.text :connection_instructions
      t.string :access_scope, null: false, default: "checked_in_guests"
      t.boolean :primary_network, null: false, default: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :hotel_wifi_networks, %i[hotel_id position]
    add_index :hotel_wifi_networks, "hotel_id, LOWER(ssid)", unique: true,
      name: "index_hotel_wifi_networks_on_hotel_and_lower_ssid"
    add_index :hotel_wifi_networks, :hotel_id, unique: true, where: "primary_network",
      name: "index_hotel_wifi_networks_on_primary_hotel"
  end
end
