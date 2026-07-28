# frozen_string_literal: true

module StayView
  class ProjectBooking
    def self.call(booking:, room_type_name:, group_rooms: [], financial_signals: [], date_window:, capabilities:)
      financial_signals = [] unless capabilities.view_financial_status?
      # Position the bar on the room's actual occupancy: once a guest has
      # physically checked in/out we honour those dates (e.g. a late checkout
      # stretches the bar into the turnover day), falling back to the scheduled
      # dates while the stay is still upcoming. Keeps the timeline aligned with
      # the operationally-aware rooms view (see ResolveRoomCardSlots).
      occupancy_check_in = booking.actual_check_in || booking.check_in
      occupancy_check_out = booking.actual_check_out || booking.check_out
      tracks = date_window.booking_tracks(occupancy_check_in, occupancy_check_out)
      guest_label = capabilities.view_booking? ? booking.guest_name.presence || "Guest" : "Reserved"
      primary_guest_name = capabilities.view_booking? ? booking.primary_guest_name.presence || guest_label : "Reserved"
      booking_type = booking.group_booking_id.present? ? :group : :single
      group_reference = booking.group_reference if capabilities.view_booking?
      group_name = booking.group_name if capabilities.view_booking?
      source = booking.source if capabilities.view_booking?
      source_label = HotelPortal::BookingSourcePresenter.new(source).label if source.present?
      adults = booking.adults if capabilities.view_booking?
      children = booking.children if capabilities.view_booking?
      boat_in_at = booking.boat_in_at&.in_time_zone(date_window.time_zone_name) if capabilities.view_booking?
      boat_out_at = booking.boat_out_at&.in_time_zone(date_window.time_zone_name) if capabilities.view_booking?
      check_in_at = booking.check_in_at&.in_time_zone(date_window.time_zone_name) if capabilities.view_booking?
      check_out_at = booking.check_out_at&.in_time_zone(date_window.time_zone_name) if capabilities.view_booking?
      actual_check_in_at = booking.actual_check_in_at&.in_time_zone(date_window.time_zone_name) if capabilities.view_booking?
      actual_check_out_at = booking.actual_check_out_at&.in_time_zone(date_window.time_zone_name) if capabilities.view_booking?
      vip = capabilities.view_booking? && booking.vip?
      blacklisted = capabilities.view_booking? && booking.blacklisted?
      repeat = capabilities.view_booking? && booking.repeat?
      room_label = booking.room_number
      dates_label = "#{booking.check_in.to_fs(:long)} to #{booking.check_out.to_fs(:long)}"
      group_label = [ group_name, group_reference ].compact_blank.join(", ")
      accessible_parts = [ guest_label, booking.status.to_s.humanize, "room #{room_label}", room_type_name, dates_label ]
      accessible_parts << "group #{group_label}" if group_label.present?
      accessible_parts << "source #{source_label}" if source_label.present?
      accessible_parts << "#{adults.to_i} adults, #{children.to_i} children" if adults.present? || children.present?
      accessible_parts << "check-in #{check_in_at.strftime('%H:%M')}" if check_in_at.present?
      accessible_parts << "check-out #{check_out_at.strftime('%H:%M')}" if check_out_at.present?
      accessible_parts << "checked in #{actual_check_in_at.strftime('%H:%M')}" if actual_check_in_at.present?
      accessible_parts << "checked out #{actual_check_out_at.strftime('%H:%M')}" if actual_check_out_at.present?
      accessible_parts << "boat-in #{boat_in_at.to_fs(:time)}" if boat_in_at.present?
      accessible_parts << "boat-out #{boat_out_at.to_fs(:time)}" if boat_out_at.present?
      guest_statuses = [ ("Blacklisted" if blacklisted), ("VIP" if vip), ("Repeat" if repeat) ].compact
      accessible_parts << "guest status #{guest_statuses.to_sentence}" if guest_statuses.any?
      accessible_parts.concat(financial_signals.map(&:label))

      BookingSegment.new(
        dom_id: "stay_view_booking_room_#{booking.booking_room_id}",
        booking_id: booking.booking_id,
        booking_room_id: booking.booking_room_id,
        guest_label: guest_label,
        primary_guest_name:,
        booking_type:,
        status: booking.status,
        check_in: booking.check_in,
        check_out: booking.check_out,
        check_in_at:,
        check_out_at:,
        actual_check_in: booking.actual_check_in,
        actual_check_out: booking.actual_check_out,
        actual_check_in_at:,
        actual_check_out_at:,
        start_track: tracks.start_track,
        end_track: tracks.end_track,
        clipped_left: tracks.clipped_left?,
        clipped_right: tracks.clipped_right?,
        accessible_label: accessible_parts.join(", "),
        capabilities: capabilities,
        group_booking_id: booking.group_booking_id,
        group_reference:,
        group_name:,
        group_position: booking.group_position,
        group_rooms: project_group_rooms(group_rooms, booking, capabilities),
        financial_signals:,
        source:,
        source_label:,
        adults:,
        children:,
        boat_in_at:,
        boat_out_at:,
        vip:,
        blacklisted:,
        repeat:
      )
    end

    def self.project_group_rooms(group_rooms, booking, capabilities)
      return [] unless capabilities.view_booking? && booking.group_booking_id.present?

      group_rooms.filter_map do |room|
        next if room.booking_id == booking.booking_id

        GroupRoomSummary.new(
          booking_id: room.booking_id,
          booking_room_id: room.booking_room_id,
          group_position: room.group_position,
          room_number: room.room_number,
          room_type_name: room.room_type_name
        )
      end
    end

    private_class_method :project_group_rooms
  end
end
