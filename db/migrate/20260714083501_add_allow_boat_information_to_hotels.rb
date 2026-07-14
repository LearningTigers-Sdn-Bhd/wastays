class AddAllowBoatInformationToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :allow_boat_information, :boolean, default: true, null: false
  end
end
