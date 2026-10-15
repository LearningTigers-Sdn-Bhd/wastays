# frozen_string_literal: true

# Hi-tea joins breakfast, lunch and dinner as a meal a boat slot can entitle a
# guest to. The service time is nullable: a property that does not serve
# hi-tea leaves it blank and no slot is pre-ticked for it.
class AddHiTeaToBoatMeals < ActiveRecord::Migration[8.1]
  def change
    add_column :hotel_boat_settings, :hi_tea_time, :time
    add_column :hotel_boat_schedules, :has_hi_tea, :boolean, default: false, null: false
  end
end
