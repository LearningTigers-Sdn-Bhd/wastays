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

  # Room-block operations only. Room status moves to the status badge dropdown
  # and housekeeping to the per-task actions in the housekeeping popover.
  def stay_view_room_actions(room, state)
    return [] unless room.capabilities.manage_room_blocks?

    return_to = state.return_path(current_hotel)
    actions = [ {
      label: "Block room",
      href: new_hotel_stay_view_room_block_path(
        current_hotel,
        room_type_id: room.room_type_id,
        room_number: room.room_number,
        start_date: state.date_window.start_date,
        return_to:
      ),
      icon: "wrench"
    } ]
    room.operational_segments.each do |segment|
      actions << {
        label: "Edit #{segment.label.downcase}",
        href: edit_hotel_stay_view_room_block_path(current_hotel, segment.room_block_id, return_to:),
        icon: "square-pen"
      }
    end
    actions
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

  def stay_view_room_menu_actions(room, state)
    # The Room View card has one menu per room, so a single stay needs no guest
    # suffix. Only disambiguate when a turnover puts more than one stay in a room.
    disambiguate = room.booking_segments.size > 1
    booking_actions = room.booking_segments.flat_map do |segment|
      stay_view_booking_actions(segment, state).map do |action|
        label = disambiguate ? "#{action[:label]} — #{segment.guest_label}" : action[:label]
        action.merge(label:)
      end
    end
    actions = stay_view_add_booking_action(room, state) + booking_actions + stay_view_room_actions(room, state)
    actions.map { |action| action.merge(data: stay_view_action_data) }
  end

  # Available-room "Add booking" entry for the Room View card menu. Mirrors the
  # availability rule the card uses (single available occupancy, no active block).
  def stay_view_add_booking_action(room, state)
    cell = room.day_cells.first
    available = cell && cell.occupancies.one? && cell.occupancies.first.state == :available
    return [] unless room.capabilities.create_booking? && available && room.operational_segments.empty?

    [ {
      label: "Add booking",
      icon: "plus",
      href: hotel_booking_transaction_new_booking_path(
        current_hotel,
        check_in: cell.date,
        check_out: cell.date + 1.day,
        room_type_id: room.room_type_id,
        room_number: room.room_number,
        return_to: state.return_path(current_hotel)
      )
    } ]
  end

  def stay_view_room_operational_status(room, state)
    ::StayView::CalculateCounts.operational_status(
      room,
      state.date_window.start_date,
      state.date_window.operational_date
    )
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
end
