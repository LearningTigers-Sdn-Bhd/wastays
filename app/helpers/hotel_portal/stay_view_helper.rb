# frozen_string_literal: true

module HotelPortal::StayViewHelper
  OCCUPANCY_LABELS = {
    available: "Available",
    arrival: "Arrival",
    occupied: "Occupied",
    departure: "Departure"
  }.freeze

  def stay_view_path_for(state, overrides = {})
    hotel_stay_view_path(current_hotel, state.query(overrides))
  end

  def stay_view_action_data
    { turbo_frame: "offcanvas_drawer", offcanvas_variant: "compact-right" }
  end

  def stay_view_booking_path(booking_id, return_to:)
    hotel_booking_transaction_show_booking_path(current_hotel, booking_id, return_to:)
  end

  def stay_view_booking_actions(segment, state)
    return_to = state.return_path(current_hotel)
    common = { return_to:, source: "stay_view" }
    actions = []
    actions << { label: "Open booking", href: stay_view_booking_path(segment.booking_id, return_to:), icon: "external-link" } if segment.capabilities.view_booking?
    if segment.capabilities.move_booking?
      actions << { label: "Move or reassign", href: edit_hotel_stay_view_booking_move_path(current_hotel, segment.booking_id, common), icon: "move" }
    end
    if segment.capabilities.change_dates?
      actions << { label: "Change dates", href: edit_hotel_stay_view_booking_dates_path(current_hotel, segment.booking_id, common), icon: "calendar-range" }
    end
    if segment.capabilities.check_in? && segment.status.in?(%i[pending confirmed])
      actions << { label: "Check in", href: hotel_booking_transaction_check_in_reservation_path(current_hotel, segment.booking_id, common), icon: "log-in" }
    end
    if segment.capabilities.check_out? && segment.status.in?(%i[checked_in review_due_out checkout_required])
      actions << { label: "Check out", href: hotel_booking_transaction_check_out_path(current_hotel, segment.booking_id, common), icon: "log-out" }
    end
    if segment.capabilities.change_dates? && segment.status.in?(%i[pending confirmed])
      actions << { label: "Mark no-show", href: hotel_booking_transaction_mark_no_show_path(current_hotel, segment.booking_id, common), icon: "user-x" }
      actions << { label: "Cancel booking", href: hotel_booking_transaction_cancel_booking_path(current_hotel, segment.booking_id, common), icon: "circle-x", variant: :danger }
    end
    actions
  end

  def stay_view_room_actions(room, state)
    return_to = state.return_path(current_hotel)
    actions = []
    if room.capabilities.manage_room_status?
      actions << {
        label: "Change room status",
        href: hotel_stay_view_room_status_path(current_hotel, room.room_type_id, room.room_number, return_to:),
        icon: "sparkles"
      }
    end
    if room.capabilities.manage_room_blocks?
      actions << {
        label: "Block room",
        href: new_hotel_stay_view_room_block_path(
          current_hotel,
          room_type_id: room.room_type_id,
          room_number: room.room_number,
          start_date: state.date_window.start_date,
          return_to:
        ),
        icon: "wrench"
      }
      room.operational_segments.each do |segment|
        actions << {
          label: "Edit #{segment.label.downcase}",
          href: edit_hotel_stay_view_room_block_path(current_hotel, segment.room_block_id, return_to:),
          icon: "square-pen"
        }
      end
    end
    actions
  end

  def stay_view_room_menu_actions(room, state)
    booking_actions = room.booking_segments.flat_map do |segment|
      stay_view_booking_actions(segment, state).map do |action|
        action.merge(label: "#{action[:label]} — #{segment.guest_label}")
      end
    end
    (booking_actions + stay_view_room_actions(room, state)).map do |action|
      action.merge(data: stay_view_action_data)
    end
  end

  def stay_view_timeline_menu_actions(room, state)
    booking_entries = room.booking_segments.filter_map do |segment|
      actions = stay_view_booking_actions(segment, state)
      next if actions.empty?

      {
        label: timeline_booking_menu_label(segment, room.booking_segments),
        id: "#{room.dom_id}-booking-#{segment.booking_id}-actions",
        children: actions.map { |action| action.merge(data: stay_view_action_data) }
      }
    end

    actions = []
    if booking_entries.any?
      actions << {
        label: "Booking",
        id: "#{room.dom_id}-booking-actions",
        children: booking_entries
      }
    end
    actions.concat(stay_view_room_actions(room, state).map { |action| action.merge(data: stay_view_action_data) })
  end

  def stay_view_occupancy_label(occupancy)
    OCCUPANCY_LABELS.fetch(occupancy.state, occupancy.state.to_s.humanize)
  end

  def stay_view_date_label(date)
    l(date, format: "%a %-d %b")
  end

  private

  def timeline_booking_menu_label(segment, segments)
    return segment.guest_label if segments.count { |candidate| candidate.guest_label == segment.guest_label } == 1

    "#{segment.guest_label} · #{segment.check_in.to_fs(:medium)}–#{segment.check_out.to_fs(:medium)}"
  end
end
