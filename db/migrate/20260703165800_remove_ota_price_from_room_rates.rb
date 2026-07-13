# frozen_string_literal: true

class RemoveOtaPriceFromRoomRates < ActiveRecord::Migration[8.0]
  def change
    remove_column :room_rates, :ota_price, :decimal, precision: 10, scale: 2
  end
end
