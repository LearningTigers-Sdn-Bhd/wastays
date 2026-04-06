class AddGuestDetailsToBookingQuotes < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_quotes, :guest_name, :string
    add_column :booking_quotes, :guest_email, :string
    add_column :booking_quotes, :guest_phone, :string
  end
end
