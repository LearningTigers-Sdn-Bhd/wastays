class Api::V1::BookingsController < Api::V1::BaseController
  def show
    # Use booking_scope to ensure authorized access
    booking = booking_scope.find_by(confirmation_token: params[:id]) || booking_scope.find(params[:id])

    unless booking
      render json: { error: "Booking not found or access denied" }, status: :not_found
      return
    end

    render json: booking.as_json(include: {
      hotel: { only: [ :id, :name, :city, :latitude, :longitude, :address ] },
      booking_rooms: { include: { room_type: { only: [ :id, :name ] } } }
    })
  end

  def reminders
    # Use booking_scope to ensure authorized access
    booking = booking_scope.find_by!(confirmation_token: params[:id])

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
