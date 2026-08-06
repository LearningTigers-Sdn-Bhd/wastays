class AddGoogleMapLinkToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :google_map_link, :string
  end
end
