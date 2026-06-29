# frozen_string_literal: true

module HotelPortal
  class RoomStatusesController < BaseController
    before_action :authorize_room_status_management!

    def update
      room_status = current_hotel.room_statuses.find(params[:id])
      board_params = params.permit(:start_date, :days, :layout).to_h

      if room_status_params.key?(:priority)
        room_status.priority = room_status_params[:priority]
      end

      if room_status_params[:status].present? && room_status_params[:status] != room_status.status_was
        result = Rooms::SetStatus.new(
          room_status: room_status,
          status: room_status_params[:status],
          user: current_user,
          reason: room_status_params[:notes]
        ).call
      else
        if room_status.save
          result = OpenStruct.new(success?: true)
        else
          result = OpenStruct.new(success?: false, error: room_status.errors.full_messages.to_sentence)
        end
      end

      if result.success?
        redirect_to hotel_room_status_board_path(current_hotel, board_params), notice: "Room status updated."
      else
        redirect_to hotel_room_status_board_path(current_hotel, board_params), alert: result.error
      end
    end

    private

    def authorize_room_status_management!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_room_status", hotel: current_hotel)
    end

    def room_status_params
      params.require(:room_status).permit(:status, :notes, :priority)
    end
  end
end
