# frozen_string_literal: true

class AddBiboTimesToBookingGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_guests, :boat_in_at, :datetime
    add_column :booking_guests, :boat_out_at, :datetime

    add_index :booking_guests, :boat_in_at
    add_index :booking_guests, :boat_out_at
  end
end
