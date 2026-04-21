class AddRatePlanToRoomRates < ActiveRecord::Migration[8.0]
  def change
    add_reference :room_rates, :rate_plan, null: true, foreign_key: true
  end
end
