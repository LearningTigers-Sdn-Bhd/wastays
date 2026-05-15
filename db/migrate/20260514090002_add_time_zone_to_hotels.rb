class AddTimeZoneToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :time_zone, :string
  end
end
