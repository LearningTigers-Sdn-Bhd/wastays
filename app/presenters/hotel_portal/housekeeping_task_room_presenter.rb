# frozen_string_literal: true

module HotelPortal
  class HousekeepingTaskRoomPresenter
    ROOM_STATUS_LABELS = ::HousekeepingTasks::BoardBuilder::ROOM_STATUS_LABELS
    INSPECTION_STATUSES = %w[awaiting_inspection inspection_failed].freeze
    INSPECTION_WORKFLOW_STATUSES = %w[cleaning awaiting_inspection inspection_failed].freeze

    BOOKING_STATUS_BADGE_VARIANTS = {
      "out_of_order" => :destructive,
      "checked_out" => :neutral,
      "checkout_required" => :destructive,
      "pending_checkout" => :warning,
      "day_use" => :info,
      "checked_in_today" => :accent,
      "in_house" => :accent,
      "day_use_reservation" => :info,
      "arriving_today" => :info,
      "vacant" => :success
    }.freeze

    attr_reader :room_number, :resolved_status, :booking, :room_type, :hotel, :view_context,
                :booking_status, :booking_status_label, :notes, :assigned_to, :assigned_to_id,
                :selected_date, :pax, :late_checkout_eligible, :room_group_id

    def initialize(room_data, hotel:, view_context:, selected_date:)
      @room_number = room_data.fetch(:room_number)
      @resolved_status = room_data.fetch(:resolved_status)
      @booking = room_data[:booking] || room_data[:active_booking]
      @room_type = room_data.fetch(:room_type)
      @room_group_id = room_data[:room_group_id]
      @room_group_name = room_data[:room_group_name]
      @hotel = hotel
      @view_context = view_context
      @booking_status = room_data.fetch(:booking_status)
      @booking_status_label = room_data.fetch(:booking_status_label)
      @notes = room_data[:notes]
      @assigned_to = room_data[:assigned_to]
      @assigned_to_id = room_data[:assigned_to_id]
      @pax = room_data.fetch(:pax)
      @late_checkout_eligible = room_data.fetch(:late_checkout_eligible, false)
      @selected_date = selected_date.to_date
    end

    def display_status
      ROOM_STATUS_LABELS.fetch(resolved_status)
    end

    def status_badge_variant
      ::Rooms::StatusPresentation.badge_variant(resolved_status)
    end

    def booking_status_badge_variant
      BOOKING_STATUS_BADGE_VARIANTS.fetch(booking_status, :neutral)
    end

    def status_choices
      allowed = ::Rooms::SetStatus::ALLOWED_TRANSITIONS.fetch(resolved_status, EMPTY_STATUSES)

      ROOM_STATUS_LABELS.filter_map do |value, label|
        next if INSPECTION_STATUSES.include?(value) && !inspection_options_visible?

        eligible = allowed.include?(value)
        eligible &&= late_checkout_eligible if value == "late_checkout_detected"
        { label:, value:, disabled: value != resolved_status && !eligible }
      end
    end

    EMPTY_STATUSES = [].freeze

    def inspection_options_visible?
      INSPECTION_WORKFLOW_STATUSES.include?(resolved_status)
    end

    def writable?
      selected_date == (hotel.current_business_date || hotel.business_date_for(Time.current))
    end

    def status_url
      view_context.hotel_housekeeping_room_status_path(
        hotel,
        room_type_id: room_type.id,
        room_number:
      )
    end

    def assignment_url
      view_context.hotel_housekeeping_room_assignment_path(
        hotel,
        room_type_id: room_type.id,
        room_number:
      )
    end

    def edit_remarks_url(return_to:)
      view_context.hotel_edit_housekeeping_room_remarks_path(
        hotel,
        room_type_id: room_type.id,
        room_number:,
        date: selected_date.iso8601,
        return_to:
      )
    end

    def remarks_url
      view_context.hotel_housekeeping_room_remarks_path(
        hotel,
        room_type_id: room_type.id,
        room_number:
      )
    end

    def assigned_to_value
      assigned_to_id.to_s
    end

    def assigned_to_name
      assigned_to&.name.presence || "Unassigned"
    end

    def remarks
      notes.presence || "No remarks"
    end

    def has_remarks?
      notes.present?
    end

    def arrival
      return "—" unless booking

      value = booking.checked_in_at || booking.check_in
      booking.checked_in_at ? view_context.display_housekeeping_datetime(value) : view_context.display_housekeeping_date(value)
    end

    def departure
      return "—" unless booking

      view_context.display_housekeeping_datetime(booking.checked_out_at || booking.check_out)
    end

    def nights
      booking ? booking.duration_in_nights : "—"
    end

    def smoking_allowed?
      room_type&.smoking_allowed
    end

    def pets_allowed?
      room_type&.pets_allowed
    end

    def dom_key
      "#{room_type.id}-#{room_number}".parameterize
    end

    def label
      "#{room_type.name} #{room_number}"
    end

    def room_group_name
      @room_group_name.presence || ::Rooms::GroupAssignmentsQuery::UNGROUPED_LABEL
    end

    def grouped? = room_group_id.present?
  end
end
