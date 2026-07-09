# frozen_string_literal: true

module HotelPortal
  class InHouseGuestPresenter
    attr_reader :booking, :time_zone

    delegate :id, :guest_name, :guest_email, :guest_phone, :confirmation_token, :vip?, :blacklisted?, :repeat?, :status, :booking_rooms, to: :booking

    STATUS_CONFIG = {
      "review_due_out" => {
        desktop_label: "Late",
        mobile_label: "Late Checkout",
        desktop_badge: "inline-flex items-center rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-bold text-amber-700 uppercase tracking-wider",
        mobile_badge: "inline-flex items-center rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-[11px] font-semibold text-amber-700"
      },
      "checkout_required" => {
        desktop_label: "Checkout required",
        mobile_label: "Checkout Required",
        desktop_badge: "inline-flex items-center rounded-full bg-rose-100 px-1.5 py-0.5 text-[10px] font-bold text-rose-700 uppercase tracking-wider",
        mobile_badge: "inline-flex items-center rounded-full border border-rose-200 bg-rose-50 px-2.5 py-1 text-[11px] font-semibold text-rose-700"
      }
    }.tap do |h|
      h.default = {
        desktop_label: "Checked in",
        mobile_label: "Checked in",
        desktop_badge: "inline-flex items-center rounded-full bg-emerald-100 px-1.5 py-0.5 text-[10px] font-bold text-emerald-700 uppercase tracking-wider",
        mobile_badge: "inline-flex items-center rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-[11px] font-semibold text-emerald-700"
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
      booking_rooms.map do |room|
        room_name = room.room_type_snapshot["name"].presence || room.room_type.name
        "#{room.quantity}x #{room_name}"
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
