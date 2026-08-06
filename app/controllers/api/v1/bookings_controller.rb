class Api::V1::BookingsController < Api::V1::BaseController
  def show
    # Use booking_scope to ensure authorized access
    booking = booking_scope.with_confirmation_token(params[:id]).first || booking_scope.find_by(id: params[:id])

    unless booking
      render json: { error: "Booking not found or access denied" }, status: :not_found
      return
    end

    render json: booking.as_json(include: {
      hotel: { only: [ :id, :name, :city, :latitude, :longitude, :address ] },
      booking_rooms: { include: { room_type: { only: [ :id, :name ] } } }
    })
  end

  def lookup
    # phone is expected in the query params
    phone = params[:phone]
    if phone.blank?
      render json: { error: "Phone number is required" }, status: :bad_request
      return
    end

    # Prioritize checked_in, then confirmed for today
    bookings = booking_scope.lookup_by_phone(phone)
                            .where(status: [ "checked_in", "confirmed" ])
                            .order(Arel.sql("CASE WHEN status = 'checked_in' THEN 0 ELSE 1 END"))
                            .order(check_in: :asc)

    booking = bookings.first

    if booking
      render json: booking.as_json(
        methods: [ :room_numbers ],
        include: {
          hotel: { only: [ :id, :name ] }
        },
        only: [ :id, :confirmation_token, :guest_name, :guest_phone, :status, :check_in, :check_out ]
      )
    else
      render json: { error: "No active booking found for this phone number" }, status: :not_found
    end
  end

  def reminders
    # Use booking_scope to ensure authorized access
    booking = booking_scope.with_confirmation_token(params[:id]).first!

    hotel = booking.hotel

    render json: {
      booking_token: booking.confirmation_token,
      guest_name: booking.guest_name,
      hotel_name: hotel.name,
      check_in_date: booking.check_in,
      check_in_time: hotel.property_policy&.check_in_time || "3:00 PM",
      location_link: "https://www.google.com/maps/search/?api=1&query=#{hotel.latitude},#{hotel.longitude}",
      address: hotel.address,
      parking_info: hotel.property_policy&.parking_policy || "Contact hotel for parking details.",
      wifi_info: "Available in all rooms",
      pre_checkin_url: hotel_pre_checkin_url(booking.confirmation_token)
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Booking not found or access denied" }, status: :not_found
  end

  private

  def hotel_pre_checkin_url(token)
    "https://wastays.com/pre-checkin/#{token}"
  end
end
