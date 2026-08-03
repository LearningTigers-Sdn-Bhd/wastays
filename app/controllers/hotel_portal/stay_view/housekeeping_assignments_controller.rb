# frozen_string_literal: true

module HotelPortal
  module StayView
    class HousekeepingAssignmentsController < BaseController
      # Either half gets you to the sheet. Whether you may assign somebody else
      # or only take the work yourself is settled by HousekeepingTasks::AssignStaff.
      before_action -> { require_any_capability!(:manage_housekeeping, :take_housekeeping_task) }
      before_action -> { require_feature!("task_assignment_minibar_log") }
      before_action :set_housekeeping_request

      def edit
        load_staff_members
      end

      def update
        HousekeepingTasks::AssignStaff.new(
          hotel: current_hotel,
          request_id: @housekeeping_request.id,
          assigned_to_id: assignment_params[:assigned_to],
          current_user:
        ).call
        respond_with_board("Room tasks assigned.", affected_room_keys: [ @room_key ])
      rescue ActiveRecord::RecordInvalid => error
        load_staff_members
        add_error(@housekeeping_request, error.record.errors.full_messages)
        render_sheet_error("hotel_portal/stay_view/housekeeping_assignments/form")
      end

      private

      def set_housekeeping_request
        @housekeeping_request = find_housekeeping_request!(params[:housekeeping_request_id])
        @room_key = housekeeping_room_key(@housekeeping_request)
      end

      def load_staff_members
        @staff_members = HotelPortal::ActiveHousekeepersQuery.new(hotel: current_hotel).call
      end

      def assignment_params
        params.fetch(:assignment, {}).permit(:assigned_to)
      end
    end
  end
end
