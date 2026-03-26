class AddCheckedInAtToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :checked_in_at, :datetime
  end
end
