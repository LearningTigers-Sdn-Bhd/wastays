class UpdateRoomRatesUniquenessIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :room_rates, name: "index_room_rates_on_room_type_id_and_date"
    add_index :room_rates, [:room_type_id, :rate_plan_id, :date], unique: true, name: "index_room_rates_on_type_plan_and_date"
  end
end
