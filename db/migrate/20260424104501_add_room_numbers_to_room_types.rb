class AddRoomNumbersToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :room_types, :room_numbers, :jsonb
  end
end
