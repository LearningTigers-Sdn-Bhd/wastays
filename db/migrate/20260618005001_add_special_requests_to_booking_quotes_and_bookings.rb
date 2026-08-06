class AddSpecialRequestsToBookingQuotesAndBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_quotes, :special_requests, :text
    add_column :bookings, :special_requests, :text
  end
end
