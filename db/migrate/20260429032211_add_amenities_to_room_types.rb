class AddAmenitiesToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :room_types, :amenities, :jsonb
  end
end
