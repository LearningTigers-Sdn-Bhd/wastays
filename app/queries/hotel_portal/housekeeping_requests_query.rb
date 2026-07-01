# frozen_string_literal: true

module HotelPortal
  class HousekeepingRequestsQuery
    def initialize(hotel:, room_number:)
      @hotel = hotel
      @room_number = room_number.to_s.strip
    end

    def call
      return HousekeepingRequest.none if @hotel.nil? || @room_number.blank?

      HousekeepingRequest.joins(:booking)
        .joins(booking: :booking_rooms)
        .where(bookings: { hotel_id: @hotel.id })
        .where(booking_rooms: { room_number: @room_number })
        .where(archived_at: nil)
        .where(status: "in_progress")
        .order(created_at: :desc)
    end
  end
end
