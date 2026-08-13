# frozen_string_literal: true

class RemoveDefaultFromHotelsSellMode < ActiveRecord::Migration[8.0]
  def change
    change_column_default :hotels, :sell_mode, from: "per_room", to: nil
  end
end
