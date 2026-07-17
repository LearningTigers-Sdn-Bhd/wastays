# frozen_string_literal: true

module HotelPortal::StayViewHelper
  OCCUPANCY_LABELS = {
    available: "Available",
    arrival: "Arrival",
    occupied: "Occupied",
    departure: "Departure"
  }.freeze
  FINANCIAL_BADGE_VARIANTS = {
    balance_due: :warning,
    credit: :warning,
    direct_bill_planned: :info,
    direct_billed: :info,
    settled: :success,
    review: :warning
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

  def stay_view_cell_actions(room, cell, state)
    return_to = state.return_path(current_hotel)
    common = {
      check_in: cell.date,
      check_out: cell.date + 1.day,
      room_type_id: room.room_type_id,
      room_number: room.room_number,
      source: "stay_view",
      return_to:
    }
    actions = []

    if room.capabilities.create_booking?
      if cell.date < state.date_window.operational_date
        actions << {
          label: "Backdated check-in",
          href: hotel_booking_transaction_backdated_check_in_path(current_hotel, common),
          icon: "history"
        }
      elsif cell.date == state.date_window.operational_date
        actions << {
          label: "Walk-in check-in",
          href: hotel_booking_transaction_walk_in_check_in_path(current_hotel, common),
          icon: "log-in"
        }
        actions << {
          label: "Add booking",
          href: hotel_booking_transaction_new_booking_path(current_hotel, common),
          icon: "calendar-plus"
        }
      else
        actions << {
          label: "Add booking",
          href: hotel_booking_transaction_new_booking_path(current_hotel, common),
          icon: "calendar-plus"
        }
      end
    end

    if room.capabilities.manage_room_blocks?
      actions << {
        label: "Maintenance block",
        href: new_hotel_stay_view_room_block_path(
          current_hotel,
          room_type_id: room.room_type_id,
          room_number: room.room_number,
          start_date: cell.date,
          return_to:
        ),
        icon: "wrench"
      }
    end

    actions.map { |action| action.merge(data: stay_view_action_data) }
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
    if room.housekeeping_alerts.any? && room.capabilities.manage_housekeeping?
      actions << {
        label: "Assign room tasks",
        href: edit_hotel_stay_view_housekeeping_request_assignment_path(
          current_hotel,
          room.housekeeping_alerts.first.request_id,
          return_to:
        ),
        icon: "user-round-check"
      }
    end
    if room.capabilities.update_housekeeping_status?
      room.housekeeping_alerts.each do |alert|
        actions << {
          label: "Update task status — #{truncate(alert.details, length: 36)}",
          href: edit_hotel_stay_view_housekeeping_request_status_path(current_hotel, alert.request_id, return_to:),
          icon: "clipboard-list"
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

  def stay_view_financial_badge_variant(signal)
    FINANCIAL_BADGE_VARIANTS.fetch(signal.state)
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
