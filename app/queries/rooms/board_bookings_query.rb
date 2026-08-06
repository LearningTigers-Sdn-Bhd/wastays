# frozen_string_literal: true

module Rooms
  class BoardBookingsQuery
    def initialize(hotel:, start_date:, end_date:)
      @hotel = hotel
      @start_date = start_date
      @end_date = end_date
    end

    def call
      @hotel.bookings
        .includes(:booking_rooms, :housekeeping_requests)
        .where(status: %w[confirmed no_show_detected checked_in due_out_detected checkout_required completed])
        .joins(:booking_rooms)
        .where("bookings.check_in::date < ? AND bookings.check_out::date > ?", @end_date + 1.day, @start_date)
        .distinct
        .order(:check_in, :id)
    end
  end
end
