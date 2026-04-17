class CorrectPayoutBatchOnBookings < ActiveRecord::Migration[8.0]
  def change
    remove_column :bookings, :payout_batch_id, :string
    add_reference :bookings, :payout_batch, null: true, foreign_key: true
  end
end
