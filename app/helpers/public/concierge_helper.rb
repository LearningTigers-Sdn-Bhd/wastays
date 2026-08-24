module Public::ConciergeHelper
  CHAT_DOODLE_ASSET = "concierge/ws-doodle-bg.png"

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

  # The guest does not need to know whether a bot or a person typed it -- they
  # are talking to the hotel either way. Staff replies are named so the guest
  # knows a human picked it up.
  def concierge_reply_author(message, hotel)
    return message.sender_user&.name.presence || "Front Desk" if message.from_staff?

    hotel.name
  end

  # A visitor who has not written yet has no conversation, so the answer to
  # "who is on the other end" comes from the hotel alone. Once there is a
  # thread, the thread knows -- and knows in the same words the live update
  # uses.
  def concierge_chat_status(conversation, hotel)
    return conversation.guest_status if conversation

    Conversation.guest_status_for(hotel)
  end

  # The doodle behind the thread, as a custom property the stylesheet picks up.
  #
  # Handed over as a mask rather than as a picture, so the pattern supplies the
  # shape and the stylesheet supplies the colour -- which is what lets a doodle
  # drawn in white ink for a dark app appear in the hotel's own green here.
  #
  # Looked up rather than asked for, and looked up in a way that can come back
  # empty: image_path raises on an asset that is not there, and a hotel without
  # a doodle must get a plain thread rather than a 500.
  def concierge_chat_doodle_style
    asset = Rails.application.assets.load_path.find(CHAT_DOODLE_ASSET)
    return if asset.blank?

    "--public-chat-doodle: url(#{image_path(CHAT_DOODLE_ASSET)});"
  end

  def concierge_room_details(booking)
    booking.booking_rooms.map do |booking_room|
      room_type_name = booking_room.room_type_snapshot&.dig("name").presence || "Room"
      room_number = booking_room.room_number.presence || "Not assigned yet"
      "#{room_type_name} - Room #{room_number}"
    end
  end
end
