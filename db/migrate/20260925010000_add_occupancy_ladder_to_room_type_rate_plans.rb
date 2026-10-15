# frozen_string_literal: true

# The anchor and steps an "Auto" per-guest price list was generated from, so
# the rate plan page can reopen it as Auto instead of as typed-in prices.
# Null for every other pricing method.
class AddOccupancyLadderToRoomTypeRatePlans < ActiveRecord::Migration[8.1]
  def change
    add_column :room_type_rate_plans, :occupancy_ladder, :jsonb
  end
end
