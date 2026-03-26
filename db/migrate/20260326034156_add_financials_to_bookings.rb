class AddFinancialsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :margin_amount, :decimal
    add_column :bookings, :net_amount, :decimal
    add_column :bookings, :margin_rate, :decimal
  end
end
