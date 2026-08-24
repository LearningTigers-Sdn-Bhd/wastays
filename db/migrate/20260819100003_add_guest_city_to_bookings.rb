# frozen_string_literal: true

class AddGuestCityToBookings < ActiveRecord::Migration[8.1]
  def change
    add_column :bookings, :guest_city, :string
  end
end
