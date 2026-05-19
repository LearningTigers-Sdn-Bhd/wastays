class AddRestrictionsToRoomRates < ActiveRecord::Migration[8.0]
  def change
    add_column :room_rates, :min_stay, :integer
    add_column :room_rates, :max_stay, :integer
    add_column :room_rates, :closed_to_arrival, :boolean
    add_column :room_rates, :closed_to_departure, :boolean
  end
end
