# frozen_string_literal: true

module Boats
  # Writes the submitted boat slots onto a booking's primary guest, resolving
  # each slot against that booking's own stay dates. Every creation and
  # check-in flow shares this so a group booked onto one boat still gets each
  # booking's own check-in and check-out dates.
  #
  # No-ops when the property has boat information off or the form did not
  # submit the fields, so callers can pass their whole params hash.
  class AssignTimes
    def self.call(booking:, params:)
      attributes = ResolveTimes.call(
        hotel: booking.hotel,
        check_in: booking.check_in,
        check_out: booking.check_out,
        params: params
      )
      return if attributes.empty?

      primary = booking.booking_guests.find(&:primary?) || booking.booking_guests.first
      primary&.update!(attributes)
    end
  end
end
