# frozen_string_literal: true

module HotelPortal
  class RoomStatusesController < BaseController
    before_action :authorize_room_status_management!

    def update
      room_status = current_hotel.room_statuses.find(params[:id])
      board_params = params.permit(:start_date, :days, :layout).to_h

      result = Rooms::UpdateStatus.new(
        room_status: room_status,
        params: room_status_params,
        user: current_user
      ).call

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
      params.require(:room_status).permit(:status, :notes, :priority, :dnd)
    end
  end
end
