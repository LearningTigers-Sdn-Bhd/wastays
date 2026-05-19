class AddGuestHomeAddressToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :guest_home_address, :string
  end
end
