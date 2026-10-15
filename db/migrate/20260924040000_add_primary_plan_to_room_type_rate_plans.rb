# frozen_string_literal: true

# The plan a room category leads with: listed first and quoted as its "from"
# price wherever guests and agents browse. At most one per category, enforced
# by the partial index. A category with none flagged behaves exactly as it did
# before (RoomType#primary_rate_plan is nil), so no backfill is needed.
class AddPrimaryPlanToRoomTypeRatePlans < ActiveRecord::Migration[8.1]
  def change
    add_column :room_type_rate_plans, :primary_plan, :boolean, default: false, null: false
    add_index :room_type_rate_plans, :room_type_id, unique: true, where: "primary_plan",
      name: "idx_room_type_rate_plans_one_primary"
  end
end
