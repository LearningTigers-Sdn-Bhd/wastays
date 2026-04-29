class AddAmenitiesToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :amenities, :jsonb, default: [], null: false
  end
end
