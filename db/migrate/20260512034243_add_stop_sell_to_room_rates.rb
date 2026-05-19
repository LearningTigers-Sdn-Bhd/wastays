class AddStopSellToRoomRates < ActiveRecord::Migration[8.0]
  def change
    add_column :room_rates, :stop_sell, :boolean
  end
end
