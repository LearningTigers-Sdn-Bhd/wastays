class UpdateUserHotelAccessToUseRole < ActiveRecord::Migration[8.0]
  def up
    add_reference :user_hotel_accesses, :role, foreign_key: true
    remove_column :user_hotel_accesses, :role, :string
  end

  def down
    add_column :user_hotel_accesses, :role, :string
    remove_reference :user_hotel_accesses, :role
  end
end
