class AddBoatTimesToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :boat_in_times, :jsonb, default: [], null: false
    add_column :hotels, :boat_out_times, :jsonb, default: [], null: false
  end
end
