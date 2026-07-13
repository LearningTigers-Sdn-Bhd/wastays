# frozen_string_literal: true

class RemoveQuantityFromBookingRooms < ActiveRecord::Migration[8.0]
  def change
    remove_column :booking_rooms, :quantity, :integer, default: 1, null: false
  end
end
