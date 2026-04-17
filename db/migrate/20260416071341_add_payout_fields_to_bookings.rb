class AddPayoutFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :payout_status, :string
    add_column :bookings, :payout_at, :datetime
    add_column :bookings, :payout_reference, :string
    add_column :bookings, :payout_batch_id, :string
  end
end
