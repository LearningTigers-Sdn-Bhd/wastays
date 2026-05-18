class AddRatePlanToBookingRooms < ActiveRecord::Migration[8.0]
  def change
    add_reference :booking_rooms, :rate_plan, null: true, foreign_key: true
  end
end
