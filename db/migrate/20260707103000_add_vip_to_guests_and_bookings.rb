# frozen_string_literal: true

class AddVipToGuestsAndBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :vip, :boolean, default: false, null: false
    add_column :bookings, :vip, :boolean, default: false, null: false
  end
end
