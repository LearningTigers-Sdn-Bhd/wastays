module Public::ConciergeHelper
  def concierge_booking_date_range(booking)
    "#{booking.check_in.strftime('%d %b')} - #{booking.check_out.strftime('%d %b %Y')}"
  end

  def concierge_booking_nights(booking)
    pluralize((booking.check_out.to_date - booking.check_in.to_date).to_i, "night")
  end

  def concierge_contact_address(hotel)
    [ hotel.address, hotel.city, hotel.country ].compact_blank.join(", ")
  end

  def concierge_location_label(hotel)
    [ hotel.city, hotel.country ].compact_blank.join(", ")
  end

  def concierge_room_details(booking)
    booking.booking_rooms.map do |booking_room|
      room_type_name = booking_room.room_type_snapshot&.dig("name").presence || "Room"
      room_number = booking_room.room_number.presence || "Not assigned yet"
      quantity_label = booking_room.quantity.to_i > 1 ? "#{booking_room.quantity}x " : ""
      "#{quantity_label}#{room_type_name} - Room #{room_number}"
    end
  end
end
