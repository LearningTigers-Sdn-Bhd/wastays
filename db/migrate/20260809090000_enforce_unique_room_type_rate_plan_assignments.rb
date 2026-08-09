# frozen_string_literal: true

class EnforceUniqueRoomTypeRatePlanAssignments < ActiveRecord::Migration[8.0]
  INDEX_NAME = "idx_room_type_rate_plans_unique_assignment"

  def change
    add_index :room_type_rate_plans,
      [ :room_type_id, :rate_plan_id ],
      unique: true,
      name: INDEX_NAME
  end
end
