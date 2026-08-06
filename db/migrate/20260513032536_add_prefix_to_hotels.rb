class AddPrefixToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :hotel_prefix, :string
    add_index :hotels, :hotel_prefix, unique: true
  end
end
