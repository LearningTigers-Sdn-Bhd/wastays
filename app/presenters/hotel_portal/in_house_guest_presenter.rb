# frozen_string_literal: true

module HotelPortal
  class InHouseGuestPresenter
    attr_reader :booking, :time_zone

    delegate :id, :guest_name, :guest_email, :guest_phone, :confirmation_token, :vip?, :blacklisted?, :repeat?, :status, :booking_rooms, to: :booking

    STATUS_CONFIG = {
      "review_due_out" => {
        desktop_label: "Late",
        mobile_label: "Late Checkout",
        desktop_badge: "inline-flex items-center rounded-full bg-warning/10 px-1.5 py-0.5 text-xs font-medium text-warning",
        mobile_badge: "inline-flex items-center rounded-full border border-warning/30 bg-warning/10 px-2.5 py-1 text-xs font-medium text-warning"
      },
      "checkout_required" => {
        desktop_label: "Checkout required",
        mobile_label: "Checkout Required",
        desktop_badge: "inline-flex items-center rounded-full bg-destructive/10 px-1.5 py-0.5 text-xs font-medium text-destructive",
        mobile_badge: "inline-flex items-center rounded-full border border-destructive/30 bg-destructive/10 px-2.5 py-1 text-xs font-medium text-destructive"
      }
    }.tap do |h|
      h.default = {
        desktop_label: "Checked in",
        mobile_label: "Checked in",
        desktop_badge: "inline-flex items-center rounded-full bg-success/10 px-1.5 py-0.5 text-xs font-medium text-success",
        mobile_badge: "inline-flex items-center rounded-full border border-success/30 bg-success/10 px-2.5 py-1 text-xs font-medium text-success"
      }
    end.freeze

    def initialize(booking, time_zone)
      @booking = booking
      @time_zone = time_zone
    end

    def check_in_formatted
      format_date(booking.check_in)
    end

    def check_out_formatted
      format_date(booking.check_out)
    end

    def checked_in_at_formatted
      format_time(booking.checked_in_at)
    end

    def status_badge_class
      STATUS_CONFIG[status][:desktop_badge]
    end

    def mobile_status_badge_class
      STATUS_CONFIG[status][:mobile_badge]
    end

    def status_label
      STATUS_CONFIG[status][:desktop_label]
    end

    def mobile_status_label
      STATUS_CONFIG[status][:mobile_label]
    end

    def rooms_assigned?
      booking_rooms.any?
    end

    def rooms_summary
      booking_rooms.group_by { |room| room.room_type_snapshot["name"].presence || room.room_type.name }.map do |room_name, rooms|
        "#{rooms.size}x #{room_name}"
      end
    end

    private

    def format_date(date)
      date&.strftime("%d %b %Y") || "—"
    end

    def format_time(time)
      time&.in_time_zone(time_zone)&.strftime("%d %b %Y, %I:%M %p") || "—"
    end
  end
end
