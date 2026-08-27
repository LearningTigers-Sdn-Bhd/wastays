# frozen_string_literal: true

module HousekeepingTasks
  class BoardBuilder
    BOOKING_STATUSES = {
      "out_of_order" => "Out of order",
      "checked_out" => "Checked out",
      "checkout_required" => "Checkout required",
      "pending_checkout" => "Pending checkout",
      "day_use" => "Day use",
      "checked_in_today" => "Checked in today",
      "in_house" => "In house",
      "day_use_reservation" => "Day-use reservation",
      "arriving_today" => "Arriving today",
      "vacant" => "Vacant"
    }.freeze

    BOOKING_STATUS_PRIORITY = BOOKING_STATUSES.keys.each_with_index.to_h.freeze
    ROOM_STATUS_LABELS = {
      "ready" => "Cleaned",
      "dirty" => "Dirty",
      "cleaning" => "Cleaning",
      "awaiting_inspection" => "Awaiting inspection",
      "inspection_failed" => "Inspection failed",
      "out_of_service" => "Out of service",
      "late_checkout_detected" => "Late checkout detected"
    }.freeze
    RELEVANT_BOOKING_STATUSES = %w[
      confirmed no_show_detected checked_in due_out_detected checkout_required completed
    ].freeze
    SORT_KEYS = %w[arrival departure].freeze
    SORT_DIRECTIONS = %w[asc desc].freeze
    GROUPINGS = %w[none room_type room_group].freeze
    DEFAULT_GROUPING = "none"
    UNGROUPED = ::Rooms::GroupAssignmentsQuery::UNGROUPED
    UNGROUPED_LABEL = ::Rooms::GroupAssignmentsQuery::UNGROUPED_LABEL
    EMPTY = [].freeze

    def initialize(hotel:, date:, room_type_ids: nil, room_statuses: nil, assigned_to_ids: nil, booking_statuses: nil,
                   room_group_ids: nil, group_by: nil, sort: nil, direction: nil, now: Time.current)
      @hotel = hotel
      @date = date.to_date
      @now = now
      @room_type_filter = normalize_filter_values(room_type_ids, &:to_i)
      @room_status_filter = normalize_filter_values(room_statuses) { |value| value.to_s if ROOM_STATUS_LABELS.key?(value.to_s) }
      @assigned_to_filter = normalize_filter_values(assigned_to_ids, &:to_i)
      @booking_status_filter = normalize_filter_values(booking_statuses) { |value| value.to_s if BOOKING_STATUSES.key?(value.to_s) }
      @room_group_filter = normalize_filter_values(room_group_ids) do |value|
        value == UNGROUPED ? UNGROUPED : Integer(value, exception: false)
      end
      @grouping = GROUPINGS.include?(group_by.to_s) ? group_by.to_s : DEFAULT_GROUPING
      @sort = SORT_KEYS.include?(sort.to_s) ? sort.to_s : nil
      @direction = SORT_DIRECTIONS.include?(direction.to_s) ? direction.to_s : "asc"
    end

    def call
      sort_rooms(filter_rooms(build_rooms))
    end

    private

    def room_key(room_type_id, room_number)
      [ room_type_id, room_number.to_s ]
    end

    def build_rooms
      room_types.flat_map do |room_type|
        directory.numbers_for(room_type.id).map { |room_number| build_room(room_type, room_number) }
      end
    end

    def build_room(room_type, room_number)
      key = room_key(room_type.id, room_number)
      persisted_status = room_statuses_by_room[key]&.first
      blocks = blocks_by_room.fetch(key, EMPTY)
      blocked = blocks.any?
      physical_status = blocked ? "out_of_service" : persisted_status&.status || "ready"
      booking_status, booking = booking_projection(
        bookings_by_room.fetch(key, EMPTY),
        out_of_order: blocked || physical_status == "out_of_service"
      )

      room_group = room_group_assignments.for(room_type.id, room_number)

      {
        room_number: room_number.to_s,
        room_type:,
        room_group_id: room_group&.id,
        room_group_name: room_group&.name || UNGROUPED_LABEL,
        room_status: persisted_status,
        resolved_status: physical_status,
        room_status_label: ROOM_STATUS_LABELS.fetch(physical_status),
        booking:,
        active_booking: booking,
        booking_status:,
        booking_status_label: BOOKING_STATUSES.fetch(booking_status),
        late_checkout_eligible: late_checkout_eligible?(booking),
        pax: booking ? "#{booking.adults}/#{booking.children || 0}" : "—",
        assigned_to: persisted_status&.assigned_to,
        assigned_to_id: persisted_status&.assigned_to_id,
        notes: persisted_status&.notes,
        blocked:
      }
    end

    # -- Preloaded data -----------------------------------------------------

    def room_types
      @room_types ||= @hotel.room_types.order(:name).to_a
    end

    def bookings_by_room
      @bookings_by_room ||= @hotel.bookings
        .where(status: RELEVANT_BOOKING_STATUSES)
        .where(
          "bookings.check_in < :next_day AND (bookings.check_out >= :day_start OR bookings.checked_out_at >= :day_start)",
          day_start: local_day.begin,
          next_day: local_day.end + 1.second
        )
        .joins(:booking_rooms)
        .select("bookings.*, booking_rooms.room_type_id AS scoped_room_type_id, booking_rooms.room_number AS scoped_room_number")
        .group_by { |booking| room_key(booking.scoped_room_type_id, booking.scoped_room_number) }
    end

    def blocks_by_room
      @blocks_by_room ||= @hotel.room_blocks
        .where(completed_at: nil)
        .where("start_date <= :date AND end_date >= :date", date: @date)
        .group_by { |block| room_key(block.room_type_id, block.room_number) }
    end

    def directory
      @directory ||= ::Rooms::DirectoryQuery.call(hotel: @hotel)
    end

    def room_group_assignments
      @room_group_assignments ||= ::Rooms::GroupAssignmentsQuery.call(hotel: @hotel, directory: directory)
    end

    def room_statuses_by_room
      @room_statuses_by_room ||= @hotel.room_statuses.includes(:assigned_to)
        .group_by { |status| room_key(status.room_type_id, status.room_number) }
    end

    # -- Booking projection ------------------------------------------------

    def booking_projection(bookings, out_of_order:)
      projections = bookings.filter_map do |booking|
        status = projected_booking_status(booking)
        [ status, booking ] if status
      end
      selected = projections.min_by { |status, booking| [ BOOKING_STATUS_PRIORITY.fetch(status), -booking.id.to_i ] }

      return [ "out_of_order", selected&.last ] if out_of_order
      selected || [ "vacant", nil ]
    end

    def projected_booking_status(booking)
      return "checked_out" if checked_out_on_selected_date?(booking)
      return "checkout_required" if booking.status == "checkout_required"
      return "pending_checkout" if booking.status == "due_out_detected"
      return "pending_checkout" if booking.status == "checked_in" && local_date(booking.check_out) == @date &&
        booking.checked_out_at.nil? && !same_day_stay?(booking)
      return "day_use" if booking.status == "checked_in" && same_day_stay?(booking)
      return "checked_in_today" if booking.status == "checked_in" && local_date(booking.checked_in_at || booking.check_in) == @date
      return "in_house" if booking.status == "checked_in"
      return "day_use_reservation" if booking.status.in?(%w[confirmed no_show_detected]) && same_day_stay?(booking)
      return "arriving_today" if booking.status.in?(%w[confirmed no_show_detected]) && local_date(booking.check_in) == @date

      nil
    end

    def checked_out_on_selected_date?(booking)
      return false unless booking.status == "completed" || booking.checked_out_at.present?

      local_date(booking.checked_out_at || booking.check_out) == @date
    end

    def same_day_stay?(booking)
      local_date(booking.check_in) == @date && local_date(booking.check_out) == @date
    end

    def local_date(value)
      value&.in_time_zone(@hotel.hotel_time_zone)&.to_date
    end

    def local_day
      @local_day ||= @date.in_time_zone(@hotel.hotel_time_zone).all_day
    end

    def late_checkout_eligible?(booking)
      @date == current_business_date &&
        booking&.status == "checked_in" &&
        booking.checked_out_at.nil? &&
        @now >= booking.check_out
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date || @hotel.business_date_for(@now)
    end

    # -- Filtering ---------------------------------------------------------

    def filter_rooms(rooms)
      predicates = [
        room_type_predicate, room_status_predicate, assigned_to_predicate, booking_status_predicate,
        room_group_predicate
      ].compact
      return rooms if predicates.empty?

      rooms.select { |room| predicates.all? { |predicate| predicate.call(room) } }
    end

    def room_type_predicate
      return if @room_type_filter.nil?

      ->(room) { @room_type_filter.include?(room[:room_type].id) }
    end

    def room_status_predicate
      return if @room_status_filter.nil?

      ->(room) { @room_status_filter.include?(room[:resolved_status]) }
    end

    def assigned_to_predicate
      return if @assigned_to_filter.nil?

      ->(room) { @assigned_to_filter.include?(room[:assigned_to_id]) }
    end

    def booking_status_predicate
      return if @booking_status_filter.nil?

      ->(room) { @booking_status_filter.include?(room[:booking_status]) }
    end

    def room_group_predicate
      return if @room_group_filter.nil?

      ->(room) { @room_group_filter.include?(room[:room_group_id] || UNGROUPED) }
    end

    def sort_rooms(rooms)
      rooms.sort { |left, right| compare_rooms(left, right) }
    end

    def compare_rooms(left, right)
      section = section_key(left) <=> section_key(right)
      return section unless section.zero?
      return natural_room_key(left) <=> natural_room_key(right) unless @sort

      left_value = booking_sort_value(left)
      right_value = booking_sort_value(right)
      return 0 if left_value.nil? && right_value.nil?
      return 1 if left_value.nil?
      return -1 if right_value.nil?

      comparison = left_value <=> right_value
      comparison = -comparison if @direction == "desc"
      comparison.zero? ? natural_room_key(left) <=> natural_room_key(right) : comparison
    end

    def booking_sort_value(room)
      booking = room[:booking]
      return if booking.nil?

      @sort == "arrival" ? (booking.checked_in_at || booking.check_in) : (booking.checked_out_at || booking.check_out)
    end

    # Sections are contiguous runs in the one ordered board, so the screen and
    # the exports read the same list.
    def section_key(room)
      case @grouping
      when "room_type" then [ 0, room[:room_type].name.to_s.downcase, room[:room_type].id.to_i ]
      when "room_group" then [ room[:room_group_id] ? 0 : 1, room[:room_group_name].to_s.downcase ]
      else EMPTY_SECTION
      end
    end

    EMPTY_SECTION = [].freeze

    def natural_room_key(room)
      room_number = room[:room_number].to_s
      parts = room_number.scan(/\d+|\D+/).map do |part|
        part.match?(/\A\d+\z/) ? [ 0, part.to_i, part.length ] : [ 1, part.downcase ]
      end
      [ parts, room[:room_type].name.to_s.downcase, room[:room_type].id.to_i ]
    end

    def normalize_filter_values(values)
      raw_values = Array(values).map(&:to_s)
      return if raw_values.empty?

      raw_values.filter_map { |value| yield(value) }.uniq
    end
  end
end
