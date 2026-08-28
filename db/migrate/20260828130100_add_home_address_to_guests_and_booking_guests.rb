# frozen_string_literal: true

class AddHomeAddressToGuestsAndBookingGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :home_address, :string
    add_column :booking_guests, :home_address_snapshot, :string
  end
end
