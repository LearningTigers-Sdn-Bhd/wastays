# frozen_string_literal: true

module HotelPortal
  class BookingPresenter
    attr_reader :booking, :hotel

    def initialize(booking, hotel)
      @booking = booking
      @hotel = hotel
    end

    def room_types
      @room_types ||= hotel.room_types.order(:name)
    end

    def booking_rooms
      @booking_rooms ||= booking.booking_rooms
    end

    def pre_checkin
      @pre_checkin ||= booking.pre_checkin
    end

    def housekeeping_requests
      @housekeeping_requests ||= booking.housekeeping_requests
                                        .where(archived_at: nil)
                                        .or(booking.housekeeping_requests.where(status: "cancelled"))
                                        .recent_first
    end

    def pending_housekeeping_requests_count
      @pending_housekeeping_requests_count ||= booking.housekeeping_requests.active.where(status: "pending").count
    end

    def complaint_requests
      @complaint_requests ||= booking.complaint_requests
                                     .where(archived_at: nil)
                                     .or(booking.complaint_requests.where(status: "cancelled"))
                                     .recent_first
    end

    def pending_complaint_requests_count
      @pending_complaint_requests_count ||= booking.complaint_requests.active.where(status: "pending").count
    end

    def pending_requests_count
      pending_housekeeping_requests_count + pending_complaint_requests_count
    end

    def notes_json
      booking.booking_notes.includes(:user).map { |n|
        {
          body: n.body,
          author: n.user.name,
          date: n.created_at.strftime("%b %d, %Y %H:%M")
        }
      }.to_json
    end
  end
end
