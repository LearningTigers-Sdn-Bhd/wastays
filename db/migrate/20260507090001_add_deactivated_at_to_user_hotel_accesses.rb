class AddDeactivatedAtToUserHotelAccesses < ActiveRecord::Migration[8.0]
  def change
    add_column :user_hotel_accesses, :deactivated_at, :datetime
    add_index :user_hotel_accesses, :deactivated_at
  end
end
