# frozen_string_literal: true

module HousekeepingTasks
  class BoardBuilder
    CHECKOUT_REQUEST_OPEN_STATUSES = %w[new assigned in_progress pending acknowledged].freeze

    # The statuses Rooms::StatusResolver reasons about. Anything else cannot
    # make a room look occupied, so it never needs loading.
    OCCUPYING_BOOKING_STATUSES = %w[confirmed review_no_show checked_in review_due_out checkout_required completed].freeze

    EMPTY = [].freeze

    def initialize(hotel:, date:, params: {})
      @hotel = hotel
      @date = date
      @params = params
    end

    def call
      filter_room_groups(build_room_groups)
    end

    private

    # A room is a room type plus a number, and numbers repeat across types, so
    # every lookup in here is keyed on the pair.
    def room_key(room_type_id, room_number)
      [ room_type_id, room_number.to_s ]
    end

    def build_room_groups
      room_types.map do |room_type|
        {
          room_type: room_type,
          rooms: room_type.room_numbers.map { |room_number| build_room(room_type, room_number) }
        }
      end
    end

    def build_room(room_type, room_number)
      key = room_key(room_type.id, room_number)

      resolved = Rooms::StatusResolver.new(
        hotel: @hotel,
        room_type: room_type,
        room_number: room_number,
        date: @date,
        bookings_scope: bookings_by_room.fetch(key, EMPTY),
        blocks_scope: blocks_by_room.fetch(key, EMPTY),
        statuses_scope: room_statuses_by_room.fetch(key, EMPTY)
      ).call

      active_booking = resolved.booking_details&.dig(:active)&.first || resolved.booking_details&.dig(:completed)&.first

      {
        room_number: room_number,
        room_type: room_type,
        resolved_status: resolved.status,
        active_booking: active_booking,
        hk_requests: task_rows_for(key, active_booking, room_number)
      }
    end

    def task_rows_for(key, active_booking, room_number)
      rows = task_rows_by_room.fetch(key, EMPTY)
      real_rows = rows.reject { |row| row.status == "no_task" }

      return real_rows if real_rows.any?
      return rows if rows.any?

      [ no_task_row(active_booking, room_number) ]
    end

    def no_task_row(active_booking, room_number)
      TaskRow.new(
        id: nil,
        booking: active_booking,
        room_number: room_number,
        request_details: "-",
        status: "no_task",
        metadata: {},
        created_at: @date.beginning_of_day,
        requested_at: @date.beginning_of_day,
        source_kind: "housekeeping"
      )
    end

    # -- Preloaded data, one query each for the whole board ------------------

    def room_types
      @room_types ||= @hotel.room_types.order(:name).to_a
    end

    # Which room types use a given number. Only needed for tasks we cannot
    # place, so that they surface somewhere rather than nowhere.
    def room_type_ids_by_number
      @room_type_ids_by_number ||= room_types.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |room_type, memo|
        room_type.room_numbers.each { |room_number| memo[room_number.to_s] << room_type.id }
      end
    end

    # A superset of the bookings covering the selected date -- check_in and
    # check_out are timestamps, and the resolver compares them as dates, so
    # the boundaries are left deliberately loose and narrowed there.
    def bookings_by_room
      @bookings_by_room ||= @hotel.bookings
        .where(status: OCCUPYING_BOOKING_STATUSES)
        .where("bookings.check_in < :next_day AND bookings.check_out >= :date", date: @date, next_day: @date + 1.day)
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
      @room_statuses_by_room ||= @hotel.room_statuses.group_by { |status| room_key(status.room_type_id, status.room_number) }
    end

    def task_rows_by_room
      @task_rows_by_room ||= begin
        rows = Hash.new { |hash, key| hash[key] = [] }
        add_housekeeping_task_rows(rows)
        add_checkout_task_rows(rows)

        rows.each_value do |list|
          list.uniq! { |row| [ row.source_kind, row.id ] }
          list.sort_by! { |row| [ row.status == "no_task" ? 1 : 0, -row.created_at.to_i ] }
        end

        rows
      end
    end

    def add_housekeeping_task_rows(rows)
      housekeeping_requests.each do |request|
        next if checkout_cleaning_housekeeping_request?(request)

        housekeeping_room_keys(request).each do |key|
          rows[key] << task_row_from_housekeeping_request(request)
        end
      end
    end

    def add_checkout_task_rows(rows)
      checkout_requests.each do |request|
        booking = request.booking
        room_number = request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number
        next if room_number.blank?

        room_keys_for(request, room_number).each do |key|
          rows[key] << task_row_from_checkout_request(request, booking, room_number)
        end
      end
    end

    def housekeeping_requests
      @housekeeping_requests ||= begin
        ids = HousekeepingRequest.open_tasks
                                 .left_joins(:booking)
                                 .where(
                                   "housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id",
                                   hotel_id: @hotel.id
                                 )
                                 .where(requested_at: ..as_of)
                                 .ids

        HousekeepingRequest.where(id: ids).includes(booking: :booking_rooms).to_a
      end
    end

    def checkout_requests
      @checkout_requests ||= begin
        ids = CheckOutRequest.joins(:booking)
                             .where(bookings: { hotel_id: @hotel.id })
                             .where(status: CHECKOUT_REQUEST_OPEN_STATUSES)
                             .where(requested_at: ..as_of)
                             .ids

        CheckOutRequest.where(id: ids).includes(booking: :booking_rooms).to_a
      end
    end

    # A request with no room number of its own belongs to whichever rooms its
    # booking holds.
    def housekeeping_room_keys(request)
      return room_keys_for(request, request.room_number) if request.room_number.present?

      Array(request.booking&.booking_rooms).filter_map do |booking_room|
        room_key(booking_room.room_type_id, booking_room.room_number) if booking_room.room_number.present?
      end
    end

    # Resolve the room type from the request's own column when it is set, and
    # otherwise from the booking room carrying that number. A request that
    # resolves to neither lands on every room type using the number: it cannot
    # be placed, and hiding the work outright is worse than showing it twice.
    def room_keys_for(request, room_number)
      room_number = room_number.to_s
      declared_room_type_id = request.room_type_id if request.respond_to?(:room_type_id)
      return [ room_key(declared_room_type_id, room_number) ] if declared_room_type_id.present?

      matching = Array(request.booking&.booking_rooms).select { |booking_room| booking_room.room_number.to_s == room_number }
      return matching.map { |booking_room| room_key(booking_room.room_type_id, room_number) } if matching.any?

      room_type_ids_by_number[room_number].map { |room_type_id| room_key(room_type_id, room_number) }
    end

    def as_of
      @as_of ||= @date.end_of_day
    end

    # -- Filtering -----------------------------------------------------------

    # Rooms are entries in RoomType#room_numbers, not rows in a table, so
    # there is nothing to filter in SQL here.
    def filter_room_groups(room_groups)
      if @params[:assigned_to].present?
        assigned_to_id = @params[:assigned_to].to_i
        room_groups.each do |group|
          group[:rooms].select! do |r|
            r[:hk_requests].any? { |req| req.metadata&.dig("assigned_to") == assigned_to_id }
          end
        end
        room_groups.select! { |group| group[:rooms].any? }
      end

      if @params[:room_status].present?
        status_val = @params[:room_status].to_s
        room_groups.each do |group|
          group[:rooms].select! { |r| r[:resolved_status] == status_val }
        end
        room_groups.select! { |group| group[:rooms].any? }
      end

      if @params[:q].present?
        q = @params[:q].downcase
        room_groups.each do |group|
          group[:rooms].select! do |r|
            r[:room_number].to_s.downcase.include?(q) ||
              group[:room_type].name.downcase.include?(q) ||
              (r[:active_booking] && (r[:active_booking].guest_name.to_s.downcase.include?(q) || r[:active_booking].confirmation_token.to_s.downcase.include?(q))) ||
              (r[:hk_requests] && r[:hk_requests].any? { |hk| hk.request_details.to_s.downcase.include?(q) })
          end
        end
        room_groups.select! { |group| group[:rooms].any? }
      end

      room_groups
    end

    # -- Row construction ----------------------------------------------------

    def task_row_from_housekeeping_request(request)
      TaskRow.new(
        id: request.id,
        booking: request.booking,
        room_number: request.room_number,
        request_details: request.request_details,
        status: request.status,
        metadata: request.metadata.to_h,
        created_at: request.created_at,
        requested_at: request.requested_at || request.created_at,
        source_kind: "housekeeping"
      )
    end

    def task_row_from_checkout_request(request, booking, room_number)
      TaskRow.new(
        id: request.id,
        booking: booking,
        room_number: room_number,
        request_details: request.guest_notes.presence || "Checkout Room Cleaning",
        status: request.status,
        metadata: request.metadata.to_h.merge("workflow_status" => request.metadata.to_h["workflow_status"].presence || HousekeepingTasks.checkout_workflow_status_for(request.status)),
        created_at: request.created_at,
        requested_at: request.requested_at,
        source_kind: "checkout"
      )
    end

    def checkout_cleaning_housekeeping_request?(request)
      request.metadata&.dig("checkout_request_id").present? || request.request_details.to_s.strip == "Checkout Room Cleaning"
    end
  end
end
