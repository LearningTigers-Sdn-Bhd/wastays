# frozen_string_literal: true

module HotelPortal
  module StayView
    class HousekeepingStatusesController < BaseController
      ALLOWED_STATUSES = %w[no_task new assigned in_progress completed].freeze

      before_action -> { require_capability!(:update_housekeeping_status) }
      before_action -> { require_feature!("task_assignment_minibar_log") }
      before_action :set_housekeeping_request

      def edit; end

      def update
        status = housekeeping_request_params[:status]
        unless ALLOWED_STATUSES.include?(status)
          add_error(@housekeeping_request, "Status is not available.")
          return render_sheet_error("hotel_portal/stay_view/housekeeping_statuses/form")
        end

        result = HotelPortal::Requests::StatusUpdater.new(
          hotel: current_hotel,
          kind: "housekeeping",
          request_id: @housekeeping_request.id,
          status:
        ).call
        return respond_with_board("Housekeeping status updated.", affected_room_keys: [ @room_key ]) if result

        add_error(@housekeeping_request, "The housekeeping status could not be updated.")
        render_sheet_error("hotel_portal/stay_view/housekeeping_statuses/form")
      end

      private

      def set_housekeeping_request
        @housekeeping_request = find_housekeeping_request!(params[:housekeeping_request_id])
        @room_key = housekeeping_room_key(@housekeeping_request)
      end

      def housekeeping_request_params
        params.require(:housekeeping_request).permit(:status)
      end
    end
  end
end
