# frozen_string_literal: true

ActiveRecord::Encryption.without_encryption do
  Booking.all.each do |booking|
    primary_guest = booking.guests.first
    puts "Booking ID: #{booking.id}"
    puts "  Guest Name (from column): #{booking.guest_name}"
    puts "  Guest Record: #{primary_guest ? "ID: #{primary_guest.id}, Name: #{primary_guest.name}" : "NIL"}"
  end
end
