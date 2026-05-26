class AddCorporatePriceToRoomRates < ActiveRecord::Migration[8.0]
  def change
    add_column :room_rates, :corporate_price, :decimal, precision: 10, scale: 2, if_not_exists: true
  end
end
