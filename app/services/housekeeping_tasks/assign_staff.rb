# frozen_string_literal: true

module HousekeepingTasks
  class AssignStaff
    def initialize(hotel:, request_id: nil, checkout_request: nil, assigned_to_id:, current_user:)
      @hotel = hotel
      @request_id = request_id
      @request = checkout_request
      @assigned_to_id = assigned_to_id.presence
      @current_user = current_user
    end

    def call
      @request ||= HousekeepingRequest.left_joins(:booking)
                                      .where(
                                        "housekeeping_requests.hotel_id = :hotel_id OR (housekeeping_requests.hotel_id IS NULL AND bookings.hotel_id = :hotel_id)",
                                        hotel_id: @hotel.id
                                      )
                                      .find(@request_id)
      raise ActiveRecord::RecordNotFound if @request.is_a?(CheckOutRequest) && @request.booking.hotel_id != @hotel.id

      room_number = request_room_number(@request)
      room_type_id = room_type_id_for(@request, room_number)
      staff = find_housekeeper if @assigned_to_id
      raise ActiveRecord::RecordNotFound, "Housekeeper not found" if @assigned_to_id && staff.nil?

      authorize_target!(staff)

      ActiveRecord::Base.transaction do
        active_requests = active_housekeeping_requests(room_number) + active_checkout_requests(room_number)
        # A room is a room type plus a number -- numbers repeat across types --
        # so tasks for 101 in another room type are a different room entirely.
        active_requests.select! { |request| room_type_id_for(request, room_number) == room_type_id }
        active_requests = [ @request.lock! ] if active_requests.empty?

        real_active = active_requests.reject { |request| request.is_a?(HousekeepingRequest) && request.status == "no_task" }
        active_requests = real_active if real_active.any?

        authorize_scope!(active_requests)
        changed_requests = []

        active_requests.each do |request|
          metadata = request.metadata.to_h
          status = request.status
          old_assignment = metadata["assigned_to"]

          if staff
            metadata, status = assign_metadata(request, metadata, status, staff)
          else
            metadata, status = unassign_metadata(request, metadata, status)
          end

          request.update!(metadata: metadata, status: status)
          changed_requests << request if old_assignment != metadata["assigned_to"]
        end

        record_audit_log(room_number, changed_requests, staff) if changed_requests.any?
      end
    end

    private

    # Dispatching is handing work to somebody; performing is doing it. A
    # performer may take unassigned work for themselves and release what is
    # already theirs, and nothing else. Enforced here rather than in a
    # controller because the housekeeping board and Stay View both land here.
    def authorize_target!(staff)
      return if dispatcher?
      raise Pundit::NotAuthorizedError unless performer?
      raise Pundit::NotAuthorizedError if staff && staff.id != @current_user.id
    end

    def authorize_scope!(requests)
      return if dispatcher?

      moves_another_persons_work = requests.any? do |request|
        assignee = request.metadata.to_h["assigned_to"]
        assignee.present? && assignee != @current_user.id
      end
      raise Pundit::NotAuthorizedError if moves_another_persons_work
    end

    def dispatcher?
      return @dispatcher if defined?(@dispatcher)

      @dispatcher = @current_user.has_permission?("dispatch_housekeeping_tasks", hotel: @hotel)
    end

    def performer?
      @current_user.has_permission?("perform_housekeeping_tasks", hotel: @hotel)
    end

    # room_type_id is nullable and rarely populated, so fall back to the
    # booking room that carries this number. Equal-and-nil counts as a match:
    # two rooms we cannot identify are no more distinguishable than one.
    def room_type_id_for(request, room_number)
      return request.room_type_id if request.respond_to?(:room_type_id) && request.room_type_id.present?

      request.booking&.booking_rooms&.find { |booking_room| booking_room.room_number.to_s == room_number.to_s }&.room_type_id
    end

    def find_housekeeper
      HotelPortal::ActiveHousekeepersQuery.new(hotel: @hotel).call.find_by(id: @assigned_to_id)
    end

    def request_room_number(request)
      return request.room_number.presence if request.respond_to?(:room_number) && request.room_number.present?

      request.metadata.to_h["room_number"].presence ||
        request.booking&.booking_rooms&.where.not(room_number: [ nil, "" ])&.first&.room_number.presence
    end

    def active_housekeeping_requests(room_number)
      return [] if room_number.blank?

      request_ids = HousekeepingRequest.left_joins(booking: :booking_rooms)
                                       .where(
                                         "housekeeping_requests.hotel_id = :hotel_id OR (housekeeping_requests.hotel_id IS NULL AND bookings.hotel_id = :hotel_id)",
                                         hotel_id: @hotel.id
                                       )
                                       .where(
                                         "housekeeping_requests.room_number = :room_number OR (housekeeping_requests.room_number IS NULL AND booking_rooms.room_number = :room_number)",
                                         room_number: room_number
                                       )
                                       .open_tasks
                                       .distinct
                                       .ids

      HousekeepingRequest.where(id: request_ids).includes(booking: :booking_rooms).lock.to_a
    end

    def active_checkout_requests(room_number)
      return [] if room_number.blank?

      request_ids = CheckOutRequest.joins(booking: :booking_rooms)
                                   .where(bookings: { hotel_id: @hotel.id })
                                   .where(status: %w[new assigned in_progress pending acknowledged])
                                   .where(
                                     "check_out_requests.metadata ->> 'room_number' = :room_number OR " \
                                     "(COALESCE(check_out_requests.metadata ->> 'room_number', '') = '' " \
                                     "AND booking_rooms.id = (SELECT MIN(first_room.id) FROM booking_rooms first_room " \
                                     "WHERE first_room.booking_id = bookings.id AND COALESCE(first_room.room_number, '') <> '') " \
                                     "AND booking_rooms.room_number = :room_number)",
                                     room_number: room_number
                                   )
                                   .distinct
                                   .ids

      CheckOutRequest.where(id: request_ids).includes(booking: :booking_rooms).lock.to_a
    end

    def assign_metadata(request, metadata, status, staff)
      if metadata["assigned_to"] != staff.id
        history = Array(metadata["assignment_history"])
        history << history_entry(assigned_to_id: staff.id, assigned_to_name: staff.name)
        metadata["assignment_history"] = history
      end
      metadata["assigned_to"] = staff.id
      metadata["assigned_to_name"] = staff.name
      metadata["workflow_status"] = "assigned" if request.is_a?(CheckOutRequest)
      status = "assigned" if status.in?(request.is_a?(CheckOutRequest) ? %w[new pending acknowledged] : %w[new no_task pending])
      [ metadata, status ]
    end

    def unassign_metadata(request, metadata, status)
      if metadata["assigned_to"].present?
        history = Array(metadata["assignment_history"])
        history << history_entry(assigned_to_name: "Unassigned")
        metadata["assignment_history"] = history
      end
      metadata.delete("assigned_to")
      metadata.delete("assigned_to_name")
      metadata["workflow_status"] = "new" if request.is_a?(CheckOutRequest)
      status = "new" if status.in?(request.is_a?(CheckOutRequest) ? %w[assigned in_progress acknowledged] : %w[assigned])
      [ metadata, status ]
    end

    def history_entry(assigned_to_name:, assigned_to_id: nil)
      {
        "assigned_to_id" => assigned_to_id,
        "assigned_to_name" => assigned_to_name,
        "assigned_by_id" => @current_user.id,
        "assigned_by_name" => @current_user.name,
        "timestamp" => Time.current.iso8601
      }.compact
    end

    def record_audit_log(room_number, requests, staff)
      reference = requests.first
      booking = reference.booking
      room = booking&.booking_rooms&.find { |booking_room| booking_room.room_number.to_s == room_number.to_s }

      RoomOperationalAuditLog.create!(
        hotel: @hotel,
        room_type: (reference.room_type if reference.respond_to?(:room_type)) || room&.room_type,
        booking: booking,
        user: @current_user,
        room_number: room_number,
        event_type: "housekeeping_assignment_changed",
        reason: staff ? "Assigned room cleaning tasks to #{staff.name}" : "Unassigned room cleaning tasks",
        metadata: {
          "assigned_to_id" => staff&.id,
          "assigned_to_name" => staff&.name,
          "tasks" => requests.map { |request| { "type" => request.class.name, "id" => request.id } }
        }.compact
      )
    end
  end
end
