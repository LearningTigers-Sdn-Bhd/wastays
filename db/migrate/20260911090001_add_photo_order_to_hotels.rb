class AddPhotoOrderToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :photo_order, :bigint, array: true, null: false, default: []
  end
end
