class AddDndToRoomStatuses < ActiveRecord::Migration[8.0]
  def change
    add_column :room_statuses, :dnd, :boolean, default: false, null: false
    add_column :room_statuses, :dnd_date, :date
    add_index :room_statuses, [ :hotel_id, :dnd, :dnd_date ]
  end
end
