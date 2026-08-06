# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomOperationsController < BaseController
      before_action -> { require_capability!(:manage_room_status) }
      before_action :set_room_status

      def edit; end

      def update
        result = Rooms::UpdateStatus.new(room_status: @room_status, params: status_params, user: current_user).call
        return respond_with_board("Room status updated.", affected_room_keys: [ room_key ]) if result.success?
        return respond_with_flag_error(result.error) if params[:flag_control].present?

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
        preselect_status
      end

      # The status badge dropdown opens this sheet preselected to the picked
      # status so it only needs to be settled, not re-chosen.
      def preselect_status
        requested = params[:status].to_s
        return unless RoomStatus::STATUSES.include?(requested)

        @room_status.status = requested
      end

      def status_params
        params.require(:room_status).permit(:status, :notes, :priority, :dnd, :priority_note)
      end

      def room_key = "#{@room_type.id}:#{@room_number}"

      def respond_with_flag_error(message)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: toast_stream(Array(message).to_sentence, type: :error), status: :unprocessable_content
          end
          format.html { redirect_to @return_to, alert: Array(message).to_sentence, status: :see_other }
        end
      end
    end
  end
end
