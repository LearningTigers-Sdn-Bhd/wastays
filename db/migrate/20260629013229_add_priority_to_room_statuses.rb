class AddPriorityToRoomStatuses < ActiveRecord::Migration[8.0]
  def change
    add_column :room_statuses, :priority, :boolean, default: false, null: false
    add_index :room_statuses, [ :hotel_id, :priority ]
  end
end
