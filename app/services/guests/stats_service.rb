# frozen_string_literal: true

module Guests
  class StatsService
    def initialize(hotel:, guest_ids:)
      @hotel = hotel
      @guest_ids = guest_ids
    end

    def call
      booking_scope = Booking
        .joins(:booking_guests)
        .where(hotel_id: @hotel.id, booking_guests: { guest_id: @guest_ids })
        .where(status: %w[checked_in completed])

      {
        stays_count: calculate_stays(booking_scope),
        currency_totals: calculate_totals(booking_scope)
      }
    end

    private

    def calculate_stays(scope)
      scope
        .group("booking_guests.guest_id")
        .distinct
        .count("bookings.id")
    end

    def calculate_totals(scope)
      scope
        .group("booking_guests.guest_id", :currency)
        .sum(:total_amount)
        .each_with_object({}) do |((guest_id, currency), amount), totals|
          totals[guest_id] ||= {}
          totals[guest_id][currency] = amount
        end
    end
  end
end
