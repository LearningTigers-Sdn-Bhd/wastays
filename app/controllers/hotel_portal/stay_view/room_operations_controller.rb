# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomOperationsController < BaseController
      before_action -> { require_capability!(:manage_room_status) }
      before_action :set_room_status

      def edit; end

      def update
        result = Rooms::UpdateStatus.new(room_status: @room_status, params: status_params, user: current_user).call
        return respond_with_board("Room status updated.") if result.success?

        add_error(@room_status, result.error)
        render_sheet_error("hotel_portal/stay_view/room_operations/form")
      end

      private

      def set_room_status
        @room_type = current_hotel.room_types.find(params[:room_type_id])
        @room_number = params[:room_number].to_s
        raise ActiveRecord::RecordNotFound unless @room_type.room_numbers.map(&:to_s).include?(@room_number)

        @room_status = current_hotel.room_statuses.find_or_initialize_by(room_type: @room_type, room_number: @room_number)
        @room_status.status ||= "ready"
      end

      def status_params
        params.require(:room_status).permit(:status, :notes)
      end
    end
  end
end
