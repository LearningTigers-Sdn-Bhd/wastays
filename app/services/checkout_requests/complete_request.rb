# frozen_string_literal: true

module CheckoutRequests
  class CompleteRequest
    def initialize(hotel:, checkout_request:)
      @hotel = hotel
      @checkout_request = checkout_request
    end

    def call
      return false unless @checkout_request.status.in?(%w[new assigned in_progress pending acknowledged])

      ActiveRecord::Base.transaction do
        request = ::HotelPortal::Requests::StatusUpdater.new(
          hotel: @hotel,
          kind: :checkout,
          request_id: @checkout_request.id,
          status: "completed"
        ).call
        raise ActiveRecord::Rollback unless request

        booking = @checkout_request.booking
        ::Bookings::TransitionStatus.new(booking: booking, status: "completed").call if booking&.checked_in?

        # Booking checkout marks assigned rooms dirty; restore the cleaning result.
        final_request = ::HotelPortal::Requests::StatusUpdater.new(
          hotel: @hotel,
          kind: :checkout,
          request_id: @checkout_request.id,
          status: "completed"
        ).call

        final_request
      end
    end
  end
end
