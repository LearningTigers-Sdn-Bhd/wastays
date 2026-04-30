class ChangeAmenitiesOnRoomTypesToNotNull < ActiveRecord::Migration[8.0]
  def change
    change_column_default :room_types, :amenities, from: nil, to: []
    change_column_null :room_types, :amenities, false, []
  end
end
