# frozen_string_literal: true

module HotelPortal
  class ArrivalPresenter
    attr_reader :booking, :hotel

    delegate :id, :guest_name, :confirmation_token, :vip?, :blacklisted?, :repeat?, :booking_rooms, :adults, :children, :status, :booking_notes, :pre_checkin, to: :booking

    def initialize(booking, hotel)
      @booking = booking
      @hotel = hotel
    end

    def room_number
      if booking.hotel_snapshot.is_a?(Hash)
        booking.hotel_snapshot["room_number"].presence || booking.hotel_snapshot.dig("assignment", "room_number").presence
      end
    end

    def room_number_label
      room_number || "TBA"
    end

    def rooms_summary
      booking_rooms.group_by { |br| br.room_type_snapshot["name"] }.map do |room_name, rooms|
        "#{rooms.size}x #{room_name}"
      end
    end

    def pre_checkin_status
      booking.pre_checkin_status || "not_started"
    end

    def pre_checkin_status_label
      pre_checkin_status.titleize
    end

    def pre_checkin_badge_class
      case pre_checkin_status
      when "completed" then "border-success/30 bg-success/10 text-success"
      when "pending" then "border-warning/30 bg-warning/10 text-warning"
      when "failed" then "border-destructive/30 bg-destructive/10 text-destructive"
      else "border-border bg-muted text-foreground"
      end
    end

    def guarantee_method_display
      booking_presenter.guarantee_method_display
    end

    def deposit_status_label
      (booking.deposit_status || "not_required").titleize
    end

    def document_uploaded?
      booking.pre_checkin&.document_status == "uploaded"
    end

    def notes_count_label
      ActionController::Base.helpers.pluralize(booking_notes.size, "note")
    end

    def has_notes?
      booking_notes.any?
    end

    private

    def booking_presenter
      @booking_presenter ||= HotelPortal::BookingPresenter.new(booking, hotel)
    end
  end
end
