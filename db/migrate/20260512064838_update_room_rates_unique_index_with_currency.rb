class UpdateRoomRatesUniqueIndexWithCurrency < ActiveRecord::Migration[8.0]
  def up
    if ActiveRecord::Base.connection.indexes(:room_rates).any? { |i| i.name == "index_room_rates_on_rt_rp_date" }
      remove_index :room_rates, name: "index_room_rates_on_rt_rp_date"
    end
    
    unless ActiveRecord::Base.connection.indexes(:room_rates).any? { |i| i.name == "index_room_rates_on_rt_rp_date_curr" }
      add_index :room_rates, [:room_type_id, :rate_plan_id, :date, :currency], unique: true, name: "index_room_rates_on_rt_rp_date_curr"
    end
  end

  def down
    if ActiveRecord::Base.connection.indexes(:room_rates).any? { |i| i.name == "index_room_rates_on_rt_rp_date_curr" }
      remove_index :room_rates, name: "index_room_rates_on_rt_rp_date_curr"
    end
    add_index :room_rates, [:room_type_id, :rate_plan_id, :date], unique: true, name: "index_room_rates_on_rt_rp_date"
  end
end
