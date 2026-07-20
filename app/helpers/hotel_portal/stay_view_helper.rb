# frozen_string_literal: true

module HotelPortal::StayViewHelper
  OCCUPANCY_LABELS = {
    available: "Available",
    arrival: "Arrival",
    occupied: "Occupied",
    departure: "Departure"
  }.freeze
  # Header copy that reframes the board for whichever view is active: the
  # timeline reads across days, the rooms view reads a single day's operations.
  BOARD_HEADER_COPY = {
    timeline: {
      description: "Plan stays across the coming days and spot turnovers before they happen.",
      caption: "Booking bars run from the middle of check-in day to the middle of checkout day. Hatched bars mark room blocks."
    }.freeze,
    rooms: {
      description: "Check room readiness and guest movements for a single day.",
      caption: "Each room card shows the selected day's arrivals, departures, and turnovers, alongside housekeeping status."
    }.freeze
  }.freeze
  DEFAULT_BOARD_HEADER_COPY = BOARD_HEADER_COPY.fetch(:timeline)
  FINANCIAL_BADGE_VARIANTS = {
    balance_due: :warning,
    credit: :warning,
    direct_bill_planned: :info,
    direct_billed: :info,
    settled: :success,
    review: :warning
  }.freeze
  # Translate authoritative lifecycle events into user-facing workflows. Undo
  # also anchors Edit Check-In, while the late-checkout drawer owns both review outcomes.
  LIFECYCLE_ACTIONS = {
    "check_in" => [
      { key: :check_in, label: "Check-in", icon: "log-in" }.freeze
    ].freeze,
    "cancel" => [
      { key: :cancel, label: "Cancel", icon: "circle-x", variant: :danger }.freeze
    ].freeze,
    "backdated_check_in" => [
      { key: :backdated_check_in, label: "Backdated Check-in", icon: "calendar-clock" }.freeze
    ].freeze,
    "mark_no_show" => [
      { key: :mark_no_show, label: "Mark No-show", icon: "user-x" }.freeze
    ].freeze,
    "check_out" => [
      { key: :check_out, label: "Check-out", icon: "log-out" }.freeze
    ].freeze,
    "undo_check_in" => [
      { key: :edit_check_in, label: "Edit Check-In", icon: "pencil" }.freeze,
      { key: :undo_check_in, label: "Undo Check-in", icon: "rotate-ccw", variant: :warning }.freeze
    ].freeze,
    "resolve_late_checkout" => [
      { key: :late_checkout, label: "Review Late Checkout", icon: "clock", variant: :warning }.freeze
    ].freeze
  }.freeze

  def stay_view_path_for(state, overrides = {})
    hotel_stay_view_path(current_hotel, state.query(overrides))
  end

  def stay_view_action_data
    { turbo_frame: "offcanvas_drawer", offcanvas_variant: "compact-right" }
  end

  def stay_view_booking_path(booking_id, return_to:, source: nil)
    hotel_booking_transaction_show_booking_path(current_hotel, booking_id, { return_to:, source: }.compact)
  end

  def stay_view_drawer_booking_actions(booking_id, capabilities:, return_to:)
    common = { return_to:, source: "stay_view" }
    actions = []
    if capabilities.move_booking?
      actions << {
        label: "Move or reassign",
        href: edit_hotel_stay_view_booking_move_path(current_hotel, booking_id, common),
        icon: "move"
      }
    end
    if capabilities.change_dates?
      actions << {
        label: "Change dates",
        href: edit_hotel_stay_view_booking_dates_path(current_hotel, booking_id, common),
        icon: "calendar-range"
      }
    end
    actions.map { |action| action.merge(data: stay_view_action_data) }
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
    actions.concat(stay_view_lifecycle_booking_actions(segment, common))
    actions.map { |action| action.merge(data: stay_view_action_data) }
  end

  def stay_view_lifecycle_booking_actions(segment, common)
    return [] unless segment.capabilities.manage_bookings?
    return [] unless segment.status.to_s.in?(Booking::OCCUPYING_STATUSES)

    Bookings::StatusLifecycle::EVENTS.fetch(segment.status.to_s, {}).keys.flat_map do |event|
      LIFECYCLE_ACTIONS.fetch(event, []).map do |presentation|
        lifecycle_booking_action(presentation, segment, common)
      end
    end
  end

  def lifecycle_booking_action(presentation, segment, common)
    key = presentation.fetch(:key)
    label = segment.status == :checkout_required && key == :check_out ? "Complete Checkout" : presentation.fetch(:label)
    href = case key
    when :check_in, :edit_check_in
      hotel_booking_transaction_check_in_reservation_path(current_hotel, segment.booking_id, common)
    when :cancel
      hotel_booking_transaction_cancel_booking_path(current_hotel, segment.booking_id, common)
    when :backdated_check_in
      hotel_booking_transaction_booking_backdated_check_in_path(current_hotel, segment.booking_id, common)
    when :mark_no_show
      hotel_booking_transaction_mark_no_show_path(current_hotel, segment.booking_id, common)
    when :check_out
      hotel_booking_transaction_check_out_path(current_hotel, segment.booking_id, common)
    when :undo_check_in
      hotel_booking_transaction_undo_check_in_path(current_hotel, segment.booking_id, common)
    when :late_checkout
      hotel_booking_transaction_late_checkout_path(current_hotel, segment.booking_id, common)
    else
      raise ArgumentError, "Unsupported Stay View lifecycle action: #{key}"
    end

    presentation.except(:key).merge(label:, href:)
  end

  # Status quick-pick items for the room-status badge dropdown. Each opens the
  # room-status sheet preselected to that status so it can be settled.
  def stay_view_status_menu_actions(room, state)
    return [] unless room.capabilities.manage_room_status?

    return_to = state.return_path(current_hotel)
    (RoomStatus::STATUSES - [ "late_checkout_detected" ]).map do |status|
      {
        label: status.humanize,
        value: status,
        current: status.to_sym == room.current_physical_status,
        href: hotel_stay_view_room_status_path(current_hotel, room.room_type_id, room.room_number, status:, return_to:),
        data: stay_view_action_data
      }
    end
  end

  # Per-task actions surfaced inside the housekeeping popover.
  def stay_view_housekeeping_task_actions(alert, room, state)
    return_to = state.return_path(current_hotel)
    actions = []
    if room.capabilities.update_housekeeping_status?
      actions << {
        label: "Update status",
        href: edit_hotel_stay_view_housekeeping_request_status_path(current_hotel, alert.request_id, return_to:),
        icon: "clipboard-list"
      }
    end
    if room.capabilities.manage_housekeeping?
      actions << {
        label: "Assign",
        href: edit_hotel_stay_view_housekeeping_request_assignment_path(current_hotel, alert.request_id, return_to:),
        icon: "user-round-check"
      }
    end
    actions.map { |action| action.merge(data: stay_view_action_data) }
  end

  def stay_view_room_slot_actions(room, state)
    date = state.date_window.start_date
    return_to = state.return_path(current_hotel)
    common = {
      check_in: date,
      check_out: date + 1.day,
      room_type_id: room.room_type_id,
      room_number: room.room_number,
      source: "stay_view",
      return_to:
    }
    actions = []

    if room.capabilities.create_booking?
      if date < state.date_window.operational_date
        actions << {
          label: "Backdated",
          aria_label: "Backdated check-in for room #{room.room_number} on #{I18n.l(date, format: :long)}",
          href: hotel_booking_transaction_backdated_check_in_path(current_hotel, common),
          icon: "history",
          variant: :secondary
        }
      elsif date == state.date_window.operational_date
        actions << {
          label: "Walk-in",
          aria_label: "Walk-in check-in for room #{room.room_number} on #{I18n.l(date, format: :long)}",
          href: hotel_booking_transaction_walk_in_check_in_path(current_hotel, common),
          icon: "log-in",
          variant: :secondary
        }
        actions << {
          label: "Book",
          aria_label: "Add booking for room #{room.room_number} on #{I18n.l(date, format: :long)}",
          href: hotel_booking_transaction_new_booking_path(current_hotel, common),
          icon: "calendar-plus",
          variant: :neutral
        }
      else
        actions << {
          label: "Book",
          aria_label: "Add booking for room #{room.room_number} on #{I18n.l(date, format: :long)}",
          href: hotel_booking_transaction_new_booking_path(current_hotel, common),
          icon: "calendar-plus",
          variant: :secondary
        }
      end
    end

    if room.capabilities.manage_room_blocks?
      actions << {
        label: "Block",
        aria_label: "Block room #{room.room_number} from #{I18n.l(date, format: :long)}",
        href: new_hotel_stay_view_room_block_path(
          current_hotel,
          room_type_id: room.room_type_id,
          room_number: room.room_number,
          start_date: date,
          source: "stay_view",
          return_to:
        ),
        icon: "wrench",
        variant: :neutral
      }
    end

    actions.map { |action| action.merge(data: stay_view_action_data) }
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

  def stay_view_board_description(view_mode)
    board_header_copy(view_mode).fetch(:description)
  end

  def stay_view_board_caption(view_mode)
    board_header_copy(view_mode).fetch(:caption)
  end

  private

  def board_header_copy(view_mode)
    BOARD_HEADER_COPY.fetch(view_mode.to_sym, DEFAULT_BOARD_HEADER_COPY)
  end
end
