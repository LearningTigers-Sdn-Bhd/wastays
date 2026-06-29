class AddCityToGuests < ActiveRecord::Migration[8.0]
  def change
    add_column :guests, :city, :string unless column_exists?(:guests, :city)
  end
end
