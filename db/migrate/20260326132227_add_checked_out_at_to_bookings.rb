class AddCheckedOutAtToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :checked_out_at, :datetime
  end
end
