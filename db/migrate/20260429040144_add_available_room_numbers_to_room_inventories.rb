class AddAvailableRoomNumbersToRoomInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :room_inventories, :available_room_numbers, :jsonb
  end
end
