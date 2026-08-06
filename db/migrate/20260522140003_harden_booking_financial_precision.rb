class HardenBookingFinancialPrecision < ActiveRecord::Migration[8.0]
  def change
    change_column :bookings, :margin_amount, :decimal, precision: 15, scale: 2
    change_column :bookings, :net_amount, :decimal, precision: 15, scale: 2
    change_column :bookings, :margin_rate, :decimal, precision: 10, scale: 4
  end
end
