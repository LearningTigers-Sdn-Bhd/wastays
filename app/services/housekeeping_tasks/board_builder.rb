# frozen_string_literal: true

module HousekeepingTasks
  class BoardBuilder
    CHECKOUT_REQUEST_OPEN_STATUSES = %w[new assigned in_progress pending acknowledged].freeze

    def initialize(hotel:, date:, params: {})
      @hotel = hotel
      @date = date
      @params = params
    end

    def call
      room_groups = build_room_groups
      filter_room_groups(room_groups)
    end

    private

    def build_room_groups
      @hotel.room_types.order(:name).map do |room_type|
        rooms_list = room_type.room_numbers.map do |room_number|
          resolved = Rooms::StatusResolver.new(
            hotel: @hotel,
            room_type: room_type,
            room_number: room_number,
            date: @date
          ).call

          active_booking = resolved.booking_details&.dig(:active)&.first || resolved.booking_details&.dig(:completed)&.first

          hk_requests = housekeeping_requests_for_room(room_type, room_number)

          real_requests = hk_requests.reject { |r| r.status == "no_task" }
          if real_requests.any?
            hk_requests = real_requests
          elsif hk_requests.empty?
            hk_requests = [
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
            ]
          end

          {
            room_number: room_number,
            room_type: room_type,
            resolved_status: resolved.status,
            active_booking: active_booking,
            hk_requests: hk_requests
          }
        end

        {
          room_type: room_type,
          rooms: rooms_list
        }
      end
    end

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

    def housekeeping_requests_for_room(room_type, room_number)
      room_number = room_number.to_s
      requests = []

      HousekeepingRequest.open_tasks.where(hotel_id: @hotel.id, room_number: room_number).find_each do |request|
        next if checkout_cleaning_housekeeping_request?(request)
        next unless belongs_to_room?(request, room_type, room_number)

        requests << task_row_from_housekeeping_request(request)
      end

      hotel_bookings_with_requests.each do |booking|
        room_matches = booking.booking_rooms.any? do |booking_room|
          booking_room.room_number.to_s == room_number && booking_room.room_type_id == room_type.id
        end
        next unless room_matches

        booking.housekeeping_requests.each do |request|
          next if request.room_number.present? && request.room_number.to_s != room_number
          next unless request.open_task?
          next if checkout_cleaning_housekeeping_request?(request)
          next unless belongs_to_room?(request, room_type, room_number)

          requests << task_row_from_housekeeping_request(request)
        end

        booking.check_out_requests.each do |request|
          next unless request.status.in?(CHECKOUT_REQUEST_OPEN_STATUSES)

          checkout_room_number = request.metadata&.dig("room_number").presence || booking.booking_rooms.first&.room_number
          next unless checkout_room_number.to_s == room_number
          next unless belongs_to_room?(request, room_type, checkout_room_number)

          requests << task_row_from_checkout_request(request, booking, checkout_room_number)
        end
      end

      requests.uniq { |request| [ request.respond_to?(:source_kind) ? request.source_kind : "housekeeping", request.id ] }
              .sort_by { |request| [ request.status == "no_task" ? 1 : 0, -request.created_at.to_i ] }
    end

    # A room is a room type plus a number, because numbers repeat across
    # types. When a request carries neither a room type nor a booking room to
    # resolve one, there is no way to tell which of them it belongs to -- show
    # it under each candidate rather than hiding the work entirely.
    def belongs_to_room?(request, room_type, room_number)
      resolved = resolved_room_type_id(request, room_number)
      resolved.nil? || resolved == room_type.id
    end

    def resolved_room_type_id(request, room_number)
      return request.room_type_id if request.respond_to?(:room_type_id) && request.room_type_id.present?

      request.booking&.booking_rooms&.find { |booking_room| booking_room.room_number.to_s == room_number.to_s }&.room_type_id
    end

    def hotel_bookings_with_requests
      @hotel_bookings_with_requests ||= @hotel.bookings.includes(:housekeeping_requests, :check_out_requests, :booking_rooms).to_a
    end

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
