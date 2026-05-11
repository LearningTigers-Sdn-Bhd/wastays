class CreateAmenities < ActiveRecord::Migration[8.0]
  def change
    create_table :amenities do |t|
      t.string :name
      t.string :slug
      t.string :icon
      t.string :category
      t.string :amenity_type
      t.string :channex_id

      t.timestamps
    end
    add_index :amenities, :slug
    add_index :amenities, :channex_id
  end
end
