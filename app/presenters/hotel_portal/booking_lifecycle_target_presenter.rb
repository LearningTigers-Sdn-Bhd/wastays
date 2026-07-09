# frozen_string_literal: true

module HotelPortal
  class BookingLifecycleTargetPresenter
    Row = Data.define(:booking, :room_type, :room_number, :guest_name, :eligible, :status_label)
    Group = Data.define(:room_type, :rows)

    ACTION_LABELS = {
      check_in: "Check-in",
      cancel: "Cancellation",
      backdated_check_in: "Backdated Check-in",
      mark_no_show: "No-show",
      reinstate: "Reinstatement",
      amend_stay: "Stay Amendment",
      edit_check_in: "Edit Check-in",
      undo_check_in: "Undo Check-in",
      checkout: "Checkout",
      late_checkout: "Late Checkout"
    }.freeze

    ELIGIBLE_STATUSES = {
      check_in: %w[confirmed],
      cancel: %w[pending confirmed review_no_show overbooked],
      backdated_check_in: %w[review_no_show],
      mark_no_show: %w[review_no_show],
      reinstate: %w[no_show],
      amend_stay: %w[pending confirmed review_no_show checked_in review_due_out checkout_required overbooked no_show],
      edit_check_in: %w[checked_in],
      undo_check_in: %w[checked_in],
      checkout: %w[checked_in checkout_required],
      late_checkout: %w[review_due_out]
    }.freeze

    def initialize(booking:, action:)
      @booking = booking
      @action = action.to_sym
    end

    attr_reader :booking, :action

    def render?
      booking.group_booking_id.present?
    end

    def action_label
      ACTION_LABELS.fetch(action)
    end

    def groups
      rows.group_by(&:room_type).sort_by { |room_type, _| room_type }.map do |room_type, grouped_rows|
        Group.new(room_type: room_type, rows: grouped_rows)
      end
    end

    def eligible_count
      rows.count(&:eligible)
    end

    def rows
      @rows ||= child_bookings.map { |child| row_for(child) }
    end

    private

    def child_bookings
      booking.group_booking.bookings
        .includes(:booking_folio, booking_rooms: :room_type, booking_guests: :guest)
        .order(:group_position, :id)
    end

    def row_for(child)
      room = child.booking_rooms.first
      eligible = eligible?(child)
      Row.new(
        booking: child,
        room_type: room&.room_type&.name.presence || room&.room_type_snapshot.to_h["name"].presence || "Unassigned",
        room_number: room&.room_number.presence || "Unassigned",
        guest_name: primary_guest_name(child),
        eligible: eligible,
        status_label: child.status.to_s.tr("_", " ").titleize
      )
    end

    def eligible?(child)
      child.status.in?(ELIGIBLE_STATUSES.fetch(action))
    end

    def primary_guest_name(child)
      primary_booking_guest = child.booking_guests.find(&:primary?) || child.booking_guests.first
      primary_booking_guest&.name_snapshot.presence || primary_booking_guest&.guest&.name.presence || child.guest_name
    end

  end
end
