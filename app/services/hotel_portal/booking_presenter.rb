# frozen_string_literal: true

module HotelPortal
  class BookingPresenter
    attr_reader :booking, :hotel

    def initialize(booking, hotel)
      @booking = booking
      @hotel = hotel
    end

    def confirmation_token
      booking.confirmation_token
    end

    def status
      booking.status
    end

    def status_label_class
      case status
      when "confirmed" then "border-green-800 text-green-800"
      when "checked_in" then "border-blue-800 text-blue-800"
      when "completed" then "border-emerald-800 text-emerald-800"
      when "cancelled" then "border-red-800 text-red-800"
      when "pending" then "border-yellow-800 text-yellow-800"
      else "border-gray-800 text-gray-800"
      end
    end

    def created_at_formatted
      booking.created_at.strftime("%d %b %Y at %H:%M")
    end

    def check_in_formatted
      booking.check_in.strftime("%d %b %Y")
    end

    def check_out_formatted
      booking.check_out.strftime("%d %b %Y")
    end

    def checked_in_at_form_value
      (booking.checked_in_at || Time.current).strftime("%Y-%m-%dT%H:%M")
    end

    def checked_out_at_form_value
      Time.current.strftime("%Y-%m-%dT%H:%M")
    end

    def requires_backdated_checkin_reason?
      hotel.night_audits.completed.where(business_date: booking.check_in.to_date).exists?
    end

    def can_manage_bookings?(user)
      user.has_permission?("manage_bookings", hotel: hotel)
    end

    def can_add_guests?(user)
      can_manage_bookings?(user) && %w[checked_in confirmed].include?(booking.status)
    end

    def additional_guests
      @additional_guests ||= booking.booking_guests.where(is_primary: false).includes(:guest)
    end

    def guest_document_type_label(guest)
      guest.document_type&.upcase || "IC/Passport"
    end

    def pre_checkin_metadata
      @pre_checkin_metadata ||= (booking.pre_checkin&.metadata || {})
    end

    def estimated_arrival_time_label
      pre_checkin_metadata["estimated_arrival_time"].presence || booking.estimated_arrival_time.presence || "Not provided"
    end

    def guest_government_id_label
      pre_checkin_metadata["guest_government_id"].presence || "Not provided"
    end

    def current_room_number
      @current_room_number ||= booking.booking_rooms.first&.room_number.presence ||
                               (if booking.hotel_snapshot.is_a?(Hash)
                                  booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence
                                end)
    end

    def payment_status_display
      status = booking.payment_status.to_s
      status == "refunded" ? "cancelled" : status
    end

    def payment_status_label_class
      display_status = payment_status_display
      case display_status
      when "captured", "completed" then "border-emerald-800 text-emerald-800"
      when "pending", "authorized" then "border-yellow-800 text-yellow-800"
      when "failed", "cancelled", "refunded" then "border-red-800 text-red-800"
      else "border-gray-800 text-gray-800"
      end
    end

    def pre_checkin_display_status
      booking.pre_checkin_display_status
    end

    def pre_checkin_status_label_class
      case pre_checkin_display_status
      when "completed" then "border-green-800 text-green-800"
      when "in_progress" then "border-blue-800 text-blue-800"
      when "failed" then "border-red-800 text-red-800"
      when "pending" then "border-yellow-800 text-yellow-800"
      else "border-gray-800 text-gray-800"
      end
    end

    def room_type_prices_json
      room_types.map { |rt| [ rt.id, rt.base_price ] }.to_h.to_json
    end

    def room_type_numbers_json
      room_types.map { |rt| [ rt.id, rt.room_numbers ] }.to_h.to_json
    end

    def room_types
      @room_types ||= hotel.room_types.order(:name)
    end

    def booking_rooms
      @booking_rooms ||= booking.booking_rooms
    end

    def room_number_for(room)
      room.room_number.presence ||
        (booking.hotel_snapshot.is_a?(Hash) ? booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence : nil)
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
