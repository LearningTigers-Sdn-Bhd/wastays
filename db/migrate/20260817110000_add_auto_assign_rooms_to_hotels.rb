# frozen_string_literal: true

class AddAutoAssignRoomsToHotels < ActiveRecord::Migration[8.1]
  # Channel-manager bookings have always been assigned a room automatically and
  # unconditionally. Defaulting to true keeps that behaviour for every existing
  # property rather than silently switching it off behind the new toggle.
  def change
    add_column :hotels, :auto_assign_rooms_enabled, :boolean, default: true, null: false
  end
end
