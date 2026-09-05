# frozen_string_literal: true

module Guests
  class GuestBookingsQuery
    def initialize(hotel:, guest:)
      @hotel = hotel
      @guest = guest
    end

    def all_bookings
      base_scope
    end

    # Two scalars for the details tab, so it never loads the booking rows.
    def stays_count
      base_scope.count
    end

    def last_checkout_on
      base_scope.maximum(:check_out)
    end

    def bookings(page: 1, per_page: 25)
      all_bookings.includes(:pre_checkin)
                  .order(check_out: :desc, id: :desc)
                  .page(page).per(per_page)
    end

    def currency_totals
      base_scope.where(status: %w[checked_in completed])
                .reorder(nil)
                .group(:currency)
                .sum(:total_amount)
    end

    private

    def base_scope
      Booking.joins(:booking_guests)
             .where(hotel_id: @hotel.id, booking_guests: { guest_id: @guest.id })
    end
  end
end
