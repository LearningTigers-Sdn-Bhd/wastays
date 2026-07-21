# frozen_string_literal: true

class RemoveInfantsFromBookingEngine < ActiveRecord::Migration[8.0]
  def change
    remove_column :bookings, :infants, :integer, default: 0, null: false
    remove_column :booking_quotes, :infants, :integer, default: 0, null: false
    remove_column :rate_plans, :infant_price_multiplier, :decimal, precision: 3, scale: 2, default: "0.0", null: false
  end
end
