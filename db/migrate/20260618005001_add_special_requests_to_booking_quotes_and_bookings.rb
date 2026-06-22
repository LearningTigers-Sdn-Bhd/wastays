class AddSpecialRequestsToBookingQuotesAndBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_quotes, :special_requests, :text unless column_exists?(:booking_quotes, :special_requests)
    add_column :bookings, :special_requests, :text unless column_exists?(:bookings, :special_requests)
  end
end
