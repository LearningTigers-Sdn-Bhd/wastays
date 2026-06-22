class AddGuestCityToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :guest_city, :string unless column_exists?(:bookings, :guest_city)
  end
end
