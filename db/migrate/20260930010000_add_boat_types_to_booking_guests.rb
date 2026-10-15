# frozen_string_literal: true

class AddBoatTypesToBookingGuests < ActiveRecord::Migration[8.0]
  def up
    %w[in out].each do |direction|
      add_column :booking_guests, "boat_#{direction}_type", :string
      backfill_type(direction)
      add_check_constraint :booking_guests,
        "boat_#{direction}_type IN ('provided', 'charter', 'own')",
        name: "booking_guests_boat_#{direction}_type_check"
    end
  end

  def down
    %w[in out].each do |direction|
      remove_check_constraint :booking_guests, name: "booking_guests_boat_#{direction}_type_check"
      remove_column :booking_guests, "boat_#{direction}_type"
    end
  end

  private

  def backfill_type(direction)
    execute "UPDATE booking_guests SET boat_#{direction}_type = 'provided' WHERE boat_#{direction}_at IS NOT NULL"
  end
end
