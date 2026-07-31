# frozen_string_literal: true

module CheckoutRequests
  # Finishing the checkout a guest asked for, which is the front desk checking
  # them out: the request is a message, and completing the message means doing
  # the thing it asked for.
  #
  # The room's cleaning is not arranged here. Departing raises it -- see
  # Bookings::TransitionStatus -- because a room needs turning over whether or
  # not anybody sent a message about it.
  class CompleteRequest
    def initialize(hotel:, checkout_request:)
      @hotel = hotel
      @checkout_request = checkout_request
    end

    def call
      return false unless @checkout_request.open_task?

      booking = @checkout_request.booking
      return false unless booking

      if ::Bookings::Occupancy.occupied?(booking)
        result = ::Bookings::TransitionStatus.new(booking: booking, status: "completed").call
        return false unless result.success?
      end

      ::HotelPortal::Requests::StatusUpdater.new(
        hotel: @hotel,
        kind: :checkout,
        request_id: @checkout_request.id,
        status: "completed"
      ).call
    end
  end
end
