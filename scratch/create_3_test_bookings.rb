# frozen_string_literal: true

# 1. Ensure Refund Policy exists
policy = RefundPolicy.first_or_initialize
policy.update!(
  min_days_before_checkin: 2,
  refund_percentage: 100.0
)
puts "Refund Policy active: #{policy.refund_percentage}% refund if >= #{policy.min_days_before_checkin} days before check-in."

# 2. Get Hotel and Room Type
hotel = Hotel.find(1)
room_type = hotel.room_types.first
user = User.find(1)

# 3. Test Data
test_guests = [
  { name: "Sarah Jenkins", email: "sarah.j@example.com", phone: "+60120000001" },
  { name: "Michael Chen", email: "m.chen@example.com", phone: "+60120000002" },
  { name: "David Miller", email: "david.miller@example.com", phone: "+60120000003" }
]

# 4. Create Bookings
test_guests.each_with_index do |guest_data, i|
  check_in = 4.days.from_now.to_date
  check_out = 5.days.from_now.to_date
  
  guest = Guest.find_or_create_by!(email: guest_data[:email]) do |g|
    g.name = guest_data[:name]
    g.phone = guest_data[:phone]
    g.country = "Malaysia"
  end

  booking = Booking.new(
    hotel: hotel,
    guest_name: guest.name,
    guest_email: guest.email,
    guest_phone: guest.phone,
    check_in: check_in,
    check_out: check_out,
    status: "confirmed",
    payment_status: "captured",
    total_amount: 180.0,
    currency: "MYR",
    adults: 2,
    source: "ota",
    confirmation_token: nil, # Will be auto-generated
    reservation_number: 20000 + i
  )
  
  booking.booking_rooms.build(
    room_type: room_type,
    quantity: 1,
    subtotal: 180.0
  )
  
  booking.save!
  
  # Create Folio
  Folios::InitializeForBooking.call(booking: booking, user: user)
  
  # Associate Guest
  booking.booking_guests.create!(guest: guest, is_primary: true)
  
  puts "Created Booking for #{guest.name}: ID=#{booking.id}, Token=#{booking.confirmation_token}, Check-in=#{booking.check_in}"
end
