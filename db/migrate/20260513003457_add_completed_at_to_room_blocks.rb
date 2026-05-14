class AddCompletedAtToRoomBlocks < ActiveRecord::Migration[8.0]
  def change
    add_column :room_blocks, :completed_at, :datetime
  end
end
