# frozen_string_literal: true

class AddInfantsAndExtraPaxPricingToBookingEngine < ActiveRecord::Migration[8.0]
  def change
    # 1. Add infants count to bookings and quotes
    add_column :bookings, :infants, :integer, default: 0, null: false
    add_column :booking_quotes, :infants, :integer, default: 0, null: false

    # 2. Add child/infant pricing multipliers to rate plans
    add_column :rate_plans, :child_price_multiplier, :decimal, precision: 3, scale: 2, default: 1.0, null: false
    add_column :rate_plans, :infant_price_multiplier, :decimal, precision: 3, scale: 2, default: 0.0, null: false

    # 3. Add base occupancy and extra pax charges to rate plans and room rates
    add_column :rate_plans, :base_occupancy, :integer, default: 2, null: false
    add_column :rate_plans, :extra_pax_charge, :decimal, precision: 10, scale: 2, default: 0.0, null: false

    add_column :room_rates, :base_occupancy, :integer
    add_column :room_rates, :extra_pax_charge, :decimal, precision: 10, scale: 2
  end
end
