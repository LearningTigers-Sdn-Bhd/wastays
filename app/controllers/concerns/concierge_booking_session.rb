module ConciergeBookingSession
  extend ActiveSupport::Concern

  included do
    helper_method :current_concierge_booking
  end

  def current_concierge_booking
    return @current_concierge_booking if defined?(@current_concierge_booking)
    @current_concierge_booking = resolve_concierge_booking
  end

  def set_concierge_booking_cookie(booking)
    expires_at = 30.minutes.from_now

    cookies.signed[:concierge_booking] = {
      value: { booking_id: booking.id, hotel_id: booking.hotel_id, exp: expires_at.to_i }.to_json,
      expires: expires_at,
      httponly: true,
      same_site: :lax
    }
  end

  def clear_concierge_booking_cookie
    cookies.delete(:concierge_booking)
  end

  private

  def resolve_concierge_booking
    raw = cookies.signed[:concierge_booking]
    return nil unless raw

    data = JSON.parse(raw)
    return nil if data["hotel_id"].to_i != @hotel.id
    return nil if data["exp"].to_i < Time.current.to_i

    @hotel.bookings.find_by(id: data["booking_id"])
  rescue JSON::ParserError
    nil
  end
end
