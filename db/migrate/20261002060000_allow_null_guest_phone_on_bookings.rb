# frozen_string_literal: true

# The desk often takes a booking before the guest gives a phone number. The
# guest adds it at check-in, so a booking may now exist without one.
class AllowNullGuestPhoneOnBookings < ActiveRecord::Migration[8.1]
  def change
    change_column_null :bookings, :guest_phone, true
  end
end
