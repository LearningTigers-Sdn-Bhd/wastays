class FixRoomRatesUniqueIndexV2 < ActiveRecord::Migration[8.0]
  def up
    if ActiveRecord::Base.connection.indexes(:room_rates).any? { |i| i.name == "index_room_rates_on_room_type_id_and_date" }
      remove_index :room_rates, name: "index_room_rates_on_room_type_id_and_date"
    end

    unless ActiveRecord::Base.connection.indexes(:room_rates).any? { |i| i.name == "index_room_rates_on_rt_rp_date" }
      add_index :room_rates, [ :room_type_id, :rate_plan_id, :date ], unique: true, name: "index_room_rates_on_rt_rp_date"
    end
  end

  def down
    if ActiveRecord::Base.connection.indexes(:room_rates).any? { |i| i.name == "index_room_rates_on_rt_rp_date" }
      remove_index :room_rates, name: "index_room_rates_on_rt_rp_date"
    end
    add_index :room_rates, [ :room_type_id, :date ], unique: true, name: "index_room_rates_on_room_type_id_and_date"
  end
end
