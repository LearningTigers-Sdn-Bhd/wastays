# frozen_string_literal: true

# Room types and rate plans are many-to-many, but the join carried only the
# price rule — occupancy lived on the rate plan and was therefore shared by
# every room the plan covered. A plan attached to a single and a suite could
# not say that one includes 1 pax and the other 4.
#
# These are nullable on purpose: null means "whatever the rate plan says", so
# existing assignments keep resolving exactly as they did before.
class AddOccupancyRulesToRoomTypeRatePlans < ActiveRecord::Migration[8.0]
  def change
    change_table :room_type_rate_plans, bulk: true do |t|
      t.integer :base_occupancy
      t.decimal :extra_pax_charge, precision: 10, scale: 2
      t.decimal :single_supplement, precision: 10, scale: 2
    end
  end
end
