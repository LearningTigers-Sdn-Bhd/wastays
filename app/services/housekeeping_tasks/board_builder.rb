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
    EMPTY = [].freeze

    def initialize(hotel:, date:, query: nil, assigned_to: nil, booking_status: nil, room_status: nil, now: Time.current)
      @hotel = hotel
      @date = date.to_date
      @now = now
      @query = query.presence&.to_s&.downcase
      @assigned_to_id = assigned_to.presence&.to_i
      # room_status is accepted temporarily so old callers fail closed while the
      # controller and exports move to the booking-centric filter contract.
      @booking_status = (booking_status.presence || room_status.presence)&.to_s
    end

    def call
      filter_room_groups(build_room_groups)
    end

    private

    def room_key(room_type_id, room_number)
      [ room_type_id, room_number.to_s ]
    end

    def build_room_groups
      room_types.filter_map do |room_type|
        rooms = room_type.room_numbers.map { |room_number| build_room(room_type, room_number) }
        { room_type:, rooms: } if rooms.any?
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

      {
        room_number: room_number.to_s,
        room_type:,
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

    def filter_room_groups(room_groups)
      predicates = [ assigned_to_predicate, booking_status_predicate, query_predicate ].compact
      return room_groups if predicates.empty?

      room_groups.filter_map do |group|
        rooms = group[:rooms].select { |room| predicates.all? { |predicate| predicate.call(group, room) } }
        { room_type: group[:room_type], rooms: } if rooms.any?
      end
    end

    def assigned_to_predicate
      return if @assigned_to_id.nil?

      ->(_group, room) { room[:assigned_to_id] == @assigned_to_id }
    end

    def booking_status_predicate
      return if @booking_status.nil?

      ->(_group, room) { room[:booking_status] == @booking_status }
    end

    def query_predicate
      return if @query.nil?

      lambda do |group, room|
        booking = room[:booking]

        matches?(room[:room_number]) ||
          matches?(group[:room_type]&.name) ||
          matches?(room[:notes]) ||
          (booking && (matches?(booking.guest_name) || matches?(booking.confirmation_token)))
      end
    end

    def matches?(value)
      value.to_s.downcase.include?(@query)
    end
  end
end
