class AddWalkInPriceToRoomRates < ActiveRecord::Migration[8.0]
  def change
    add_column :room_rates, :walk_in_price, :decimal, precision: 10, scale: 2
  end
end
