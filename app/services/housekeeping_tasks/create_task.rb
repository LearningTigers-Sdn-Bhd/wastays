# frozen_string_literal: true

module HousekeepingTasks
  # Adds a task to a room that needs work but has none asked of it yet.
  #
  # The task belongs to the room rather than to a stay: a room needing cleaning
  # is usually one its guest has already left, and hanging the work off their
  # booking would file it under a departed guest. So it carries the hotel, the
  # room type and the number, and no booking.
  class CreateTask
    # Which rooms may be given work this way. A room already being cleaned, or
    # occupied, or out of service, is not waiting for somebody to name a task.
    ELIGIBLE_STATUSES = %w[dirty].freeze

    def initialize(hotel:, room_type:, room_number:, details:, current_user:, assigned_to_id: nil)
      @hotel = hotel
      @room_type = room_type
      @room_number = room_number.to_s
      @details = details.to_s.strip
      @assigned_to_id = assigned_to_id.presence
      @current_user = current_user
    end

    def call
      return Result.failure("Enter what needs doing.") if @details.blank?
      return Result.failure("Room #{@room_number} is not waiting for a task.") unless eligible_room?

      task = nil
      ActiveRecord::Base.transaction do
        task = create_task
        assign(task) if @assigned_to_id
      end

      Result.success(task: task.reload)
    end

    private

    def create_task
      HousekeepingRequest.create!(
        hotel: @hotel,
        room_type: @room_type,
        room_number: @room_number,
        work_context: "vacant_room_task",
        request_details: @details,
        status: "new",
        # The board only shows work already asked for as of the date being
        # looked at, so a task added now is asked for now.
        requested_at: Time.current,
        metadata: {
          "source" => "housekeeping_board",
          "created_by_id" => @current_user.id,
          "created_by_name" => @current_user.name
        }
      )
    end

    # Assigning is its own job, done in its own service -- which also writes the
    # assignment history and the audit event, and refuses a caller who may not
    # hand work to the person named.
    def assign(task)
      AssignStaff.new(
        hotel: @hotel,
        request_id: task.id,
        assigned_to_id: @assigned_to_id,
        current_user: @current_user
      ).call
    end

    def eligible_room?
      resolved = Rooms::StatusResolver.new(
        hotel: @hotel,
        room_type: @room_type,
        room_number: @room_number,
        date: Date.current
      ).call

      resolved.status.in?(ELIGIBLE_STATUSES) && resolved.booking_state != :occupied
    end
  end
end
