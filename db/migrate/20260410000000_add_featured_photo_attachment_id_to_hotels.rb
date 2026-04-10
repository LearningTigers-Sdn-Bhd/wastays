class AddFeaturedPhotoAttachmentIdToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :featured_photo_attachment_id, :bigint
    add_index :hotels, :featured_photo_attachment_id
  end
end
