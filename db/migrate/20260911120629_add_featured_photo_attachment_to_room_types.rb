class AddFeaturedPhotoAttachmentToRoomTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :room_types, :featured_photo_attachment_id, :bigint
    add_index :room_types, :featured_photo_attachment_id
  end
end
