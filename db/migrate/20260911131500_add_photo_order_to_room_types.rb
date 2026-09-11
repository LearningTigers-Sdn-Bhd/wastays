class AddPhotoOrderToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :room_types, :photo_order, :bigint, array: true, null: false, default: []
  end
end
