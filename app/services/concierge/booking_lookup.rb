module Concierge
  class BookingLookup
    def initialize(hotel:, confirmation_token:, last_name: nil, request_ip: nil)
      @hotel = hotel
      @token = confirmation_token.to_s.strip.upcase
    end

    def call
      booking = @hotel.bookings.find_by(confirmation_token: @token)
      return failure(:not_found) unless booking

      Result.success(booking: booking)
    end

    private

    def failure(code)
      Result.failure(error_code: code)
    end
  end
end
