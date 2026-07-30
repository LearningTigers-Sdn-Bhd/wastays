# frozen_string_literal: true

module HotelPortal
  # Sheet-based actions launched from the housekeeping board.
  #
  # Named HousekeepingActions rather than HousekeepingTasks::Actions on purpose:
  # a HotelPortal::HousekeepingTasks would shadow the top-level HousekeepingTasks
  # for every constant lookup inside HotelPortal, the board controller included.
  module HousekeepingActions
    # "Add a task to this room", as a sheet on the housekeeping board.
    #
    # Renders the form into the requesting sheet frame (GET) and adds the task
    # (POST). Naming the work and deciding whether a room can be given any
    # belongs to HousekeepingTasks::CreateTask; this authorizes the caller, reads
    # the room off the params, and reports the outcome.
    class TaskCreationsController < HotelPortal::BaseController
      include HousekeepingTaskAuthorization
      include HousekeepingActionCompletion

      before_action :authorize_dispatch!
      before_action -> { require_feature!("task_assignment_minibar_log") }
      before_action :set_room
      before_action :set_return_to

      def show
        return create if request.post?

        @staff_members = ActiveHousekeepersQuery.new(hotel: current_hotel).call
        render :show, layout: false
      end

      private

      def create
        result = ::HousekeepingTasks::CreateTask.new(
          hotel: current_hotel,
          room_type: @room_type,
          room_number: @room_number,
          details: params[:request_details],
          assigned_to_id: params[:assigned_to],
          current_user: current_user
        ).call

        return complete_housekeeping_action(destination: @return_to, notice: "Task added.") if result.success?

        @error = result.error
        @staff_members = ActiveHousekeepersQuery.new(hotel: current_hotel).call
        render :show, layout: false, status: :unprocessable_content
      end

      # Only a dispatcher hands work out, so only a dispatcher names new work to
      # hand out. A performer takes what is already on the board.
      def authorize_dispatch!
        raise Pundit::NotAuthorizedError unless dispatch_housekeeping?
      end

      # A room number means nothing without its room type -- numbers repeat
      # across types -- and a number the type does not have is not a room.
      def set_room
        @room_type = current_hotel.room_types.find(params[:room_type_id])
        @room_number = params[:room_number].to_s

        raise ActiveRecord::RecordNotFound unless @room_type.room_numbers.map(&:to_s).include?(@room_number)
      end

      def set_return_to
        @return_to = housekeeping_action_return_to(fallback: hotel_housekeeping_tasks_path(current_hotel))
      end
    end
  end
end
