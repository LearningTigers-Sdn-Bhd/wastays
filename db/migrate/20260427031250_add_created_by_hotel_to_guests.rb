class AddCreatedByHotelToGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :created_by_hotel_id, :bigint
    add_index :guests, :created_by_hotel_id
  end
end
