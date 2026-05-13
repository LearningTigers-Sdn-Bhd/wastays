class AddNumbersToBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :bookings, :reservation_number, :integer
    add_column :bookings, :folio_number, :integer
    add_column :bookings, :receipt_number, :integer
    add_column :bookings, :guest_registration_number, :integer
  end
end
