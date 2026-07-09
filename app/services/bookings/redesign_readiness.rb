# frozen_string_literal: true

module Bookings
  class RedesignReadiness
    def self.call
      new.call
    end

    def call
      {
        bookings_with_multiple_room_rows: Booking.joins(:booking_rooms).group("bookings.id").having("COUNT(booking_rooms.id) > 1").count.size,
        duplicate_primary_guests: duplicate_primary_scope.count.size,
        missing_primary_guests: missing_primary_scope.count,
        duplicate_booking_guests: duplicate_guest_scope.count.size,
        bookings_without_rooms: Booking.left_joins(:booking_rooms).where(booking_rooms: { id: nil }).count
      }
    end

    private

    def duplicate_primary_scope
      BookingGuest.where(is_primary: true).group(:booking_id).having("COUNT(*) > 1")
    end

    def missing_primary_scope
      Booking.where.not(status: "pending")
        .where.not(id: BookingGuest.where(is_primary: true).select(:booking_id))
    end

    def duplicate_guest_scope
      BookingGuest.group(:booking_id, :guest_id).having("COUNT(*) > 1")
    end
  end
end
