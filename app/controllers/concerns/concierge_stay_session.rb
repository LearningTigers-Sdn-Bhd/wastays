# frozen_string_literal: true

# Authorizes one browser for one stay.
#
# The cookie is the only credential. The stay link in the URL identifies the
# stay, and it never authenticates a device. More than one browser can hold a
# valid session for the same stay, because each one verifies on its own.
#
# Every read tests the hotel, the record, the booking, and the eligibility
# again. A revoked record or a booking that left its stay window ends the
# session on the next request, with no job and no sweep.
module ConciergeStaySession
  extend ActiveSupport::Concern

  COOKIE_NAME = :concierge_stay

  included do
    helper_method :current_concierge_stay
  end

  def current_concierge_stay
    return @current_concierge_stay if defined?(@current_concierge_stay)

    @current_concierge_stay = resolve_concierge_stay
  end

  def start_concierge_stay_session(stay_access, expires_at:)
    cookies.signed[COOKIE_NAME] = {
      value: {
        stay_access_id: stay_access.stay_access_id,
        hotel_id: stay_access.hotel_id,
        booking_id: stay_access.booking_id,
        exp: expires_at.to_i
      }.to_json,
      expires: expires_at,
      httponly: true,
      secure: request.ssl?,
      same_site: :lax
    }

    remove_instance_variable(:@current_concierge_stay) if defined?(@current_concierge_stay)
  end

  def clear_concierge_stay_session
    cookies.delete(COOKIE_NAME)
    @current_concierge_stay = nil
  end

  private

  def resolve_concierge_stay
    raw = cookies.signed[COOKIE_NAME]
    return nil if raw.blank?

    data = JSON.parse(raw)
    return nil unless session_matches_hotel?(data)
    return nil if data["exp"].to_i <= Time.current.to_i

    record = live_stay_access(data["stay_access_id"])
    return nil if record.blank?
    return nil if record.booking_id != data["booking_id"].to_i
    return nil unless stay_still_eligible?(record)

    record
  rescue JSON::ParserError
    nil
  end

  def session_matches_hotel?(data)
    @hotel.present? && data["hotel_id"].to_i == @hotel.id
  end

  def live_stay_access(stay_access_id)
    return nil if stay_access_id.blank?

    ConciergeStayAccess.for_hotel(@hotel).live.find_by(stay_access_id: stay_access_id)
  end

  def stay_still_eligible?(record)
    Concierge::StayAccess::Eligibility.new(booking: record.booking).call.success?
  end
end
