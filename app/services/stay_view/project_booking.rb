# frozen_string_literal: true

module StayView
  class ProjectBooking
    def self.call(booking:, room_type_name:, date_window:, capabilities:)
      tracks = date_window.booking_tracks(booking.check_in, booking.check_out)
      guest_label = capabilities.view_booking? ? booking.guest_name.presence || "Guest" : "Reserved"
      room_label = booking.room_number
      dates_label = "#{booking.check_in.to_fs(:long)} to #{booking.check_out.to_fs(:long)}"

      BookingSegment.new(
        dom_id: "stay_view_booking_room_#{booking.booking_room_id}",
        booking_id: booking.booking_id,
        booking_room_id: booking.booking_room_id,
        guest_label: guest_label,
        status: booking.status,
        check_in: booking.check_in,
        check_out: booking.check_out,
        start_track: tracks.start_track,
        end_track: tracks.end_track,
        clipped_left: tracks.clipped_left?,
        clipped_right: tracks.clipped_right?,
        accessible_label: "#{guest_label}, #{booking.status.to_s.humanize}, room #{room_label}, #{room_type_name}, #{dates_label}",
        capabilities: capabilities
      )
    end
  end
end
