class AddRoomNumberToBookingRooms < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_rooms, :room_number, :string
  end
end
