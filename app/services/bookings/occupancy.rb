# frozen_string_literal: true

module Bookings
  module Occupancy
    OCCUPIED_STATUSES = Booking::OCCUPIED_STATUSES

    # A guest may ask for something before they arrive as well as while they are
    # in the room: "have extra towels ready" is a real request, and the stay it
    # belongs to is the one they are about to start. Wider than OCCUPIED_STATUSES
    # by the two statuses a booking holds between being made and being checked in.
    GUEST_REQUEST_STATUSES = (%w[confirmed no_show_detected] + OCCUPIED_STATUSES).freeze

    def self.occupied?(booking)
      booking.present? && booking.status.in?(OCCUPIED_STATUSES)
    end

    # Whether this booking is one a guest can still raise a request against.
    # Not the same question as whether the room is occupied: the room decides
    # who does the work, the stay decides whether there is anybody to do it for.
    def self.accepts_guest_requests?(booking)
      booking.present? && booking.status.in?(GUEST_REQUEST_STATUSES)
    end
  end
end
