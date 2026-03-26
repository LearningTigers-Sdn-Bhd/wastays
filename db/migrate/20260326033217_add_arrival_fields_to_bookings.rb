class AddArrivalFieldsToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :pre_checkin_status, :string
    add_column :bookings, :guarantee_method, :string
    add_column :bookings, :deposit_status, :string
  end
end
