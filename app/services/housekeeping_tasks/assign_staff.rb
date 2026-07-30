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
      @request ||= housekeeping_request_in_this_hotel
      raise ActiveRecord::RecordNotFound unless belongs_to_hotel?(@request)

      room_number = request_room_number(@request)
      room_type_id = room_type_id_for(@request, room_number)
      staff = find_housekeeper if @assigned_to_id
      raise ActiveRecord::RecordNotFound, "Housekeeper not found" if @assigned_to_id && staff.nil?

      authorize_target!(staff)

      ActiveRecord::Base.transaction do
        assignments = room_assignments(room_number, room_type_id)
        authorize_scope!(assignments)

        changed = assignments.select { |assignment| assignment.hand_over(staff, by: @current_user) }
        record_audit_log(room_number, changed, staff) if changed.any?
      end
    end

    private

    def housekeeping_request_in_this_hotel
      HousekeepingRequest.in_hotel(@hotel).find(@request_id)
    end

    # A record handed straight in has not been through the finder above, so its
    # hotel is still to be checked -- by its own column when it has one, and
    # otherwise by the booking it hangs off.
    def belongs_to_hotel?(record)
      owner_id = record.try(:hotel_id) || record.booking&.hotel_id

      owner_id == @hotel.id
    end

    # Everything open on the one room this task belongs to, so that taking a room
    # takes all of its work at once. A room is a room type plus a number --
    # numbers repeat across types -- so tasks for 101 in another room type are a
    # different room entirely. Placeholder records come along only when the room
    # has nothing else, since they stand for the absence of the work.
    def room_assignments(room_number, room_type_id)
      tasks = active_housekeeping_requests(room_number) + active_checkout_requests(room_number)
      tasks.select! { |task| room_type_id_for(task, room_number) == room_type_id }
      return TaskAssignment.wrap([ @request.lock! ]) if tasks.empty?

      assignments = TaskAssignment.wrap(tasks)
      real_work = assignments.reject(&:placeholder?)
      real_work.any? ? real_work : assignments
    end

    # Dispatching is handing work to somebody; performing is doing it. A
    # performer may take unassigned work for themselves and release what is
    # already theirs, and nothing else. Enforced here rather than in a
    # controller because the housekeeping board and Stay View both land here.
    def authorize_target!(staff)
      return if dispatcher?
      raise Pundit::NotAuthorizedError unless performer?
      raise Pundit::NotAuthorizedError if staff && staff.id != @current_user.id
    end

    def authorize_scope!(assignments)
      return if dispatcher?

      moves_another_persons_work = assignments.any? { |assignment| assignment.held_by_somebody_else?(@current_user) }
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

      request_ids = HousekeepingRequest.in_hotel(@hotel)
                                       .left_joins(booking: :booking_rooms)
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
                                   .open_tasks
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

    def record_audit_log(room_number, assignments, staff)
      reference = assignments.first.record
      booking = reference.booking
      room = booking&.booking_rooms&.find { |booking_room| booking_room.room_number.to_s == room_number.to_s }

      RoomOperationalAuditLog.create!(
        hotel: @hotel,
        room_type: reference.try(:room_type) || room&.room_type,
        booking: booking,
        user: @current_user,
        room_number: room_number,
        event_type: "housekeeping_assignment_changed",
        reason: staff ? "Assigned room cleaning tasks to #{staff.name}" : "Unassigned room cleaning tasks",
        metadata: {
          "assigned_to_id" => staff&.id,
          "assigned_to_name" => staff&.name,
          "tasks" => assignments.map(&:audit_entry)
        }.compact
      )
    end
  end
end
