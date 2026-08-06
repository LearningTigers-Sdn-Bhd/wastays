# frozen_string_literal: true

module NightAudits
  class FinanciallyRelevantBookings
    STATUSES = %w[checked_in due_out_detected checkout_required completed].freeze

    def self.call(hotel:, business_date:)
      new(hotel:, business_date:).call
    end

    def initialize(hotel:, business_date:)
      @hotel = hotel
      @business_date = business_date.to_date
    end

    def call
      stay_scope.or(no_show_scope)
        .includes(:payment_transactions, :refund_request, :booking_rooms, booking_folio: :folio_transactions)
    end

    private

    def bookings
      @bookings ||= @hotel.bookings
    end

    def stay_scope
      bookings
        .where(status: STATUSES)
        .intersecting_local_date(@business_date, @hotel.hotel_time_zone)
    end

    def no_show_scope
      bookings.no_show.checking_in_on(@business_date, @hotel.hotel_time_zone)
    end
  end
end
