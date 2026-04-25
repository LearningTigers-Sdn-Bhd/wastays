class AddRoomNumberModeToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :room_types, :room_number_mode, :string
  end
end
