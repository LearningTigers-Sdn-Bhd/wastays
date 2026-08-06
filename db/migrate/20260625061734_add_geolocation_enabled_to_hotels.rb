class AddGeolocationEnabledToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :geolocation_enabled, :boolean, default: true, null: false
  end
end
