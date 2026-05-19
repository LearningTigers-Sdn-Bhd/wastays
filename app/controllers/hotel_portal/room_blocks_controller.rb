# frozen_string_literal: true

module HotelPortal
  class RoomBlocksController < BaseController
    before_action :authorize_room_block_management!

    def create
      result = Rooms::ManageBlock.new(
        hotel: current_hotel,
        user: current_user,
        params: room_block_params
      ).create

      if result.success?
        redirect_to hotel_room_status_board_path(current_hotel, board_params), notice: "Room blocked for maintenance."
      else
        redirect_to hotel_room_status_board_path(current_hotel, board_params), alert: result.error
      end
    end

    def update
      block = current_hotel.room_blocks.find(params[:id])
      result = Rooms::ManageBlock.new(
        hotel: current_hotel,
        user: current_user,
        block: block,
        params: room_block_params
      ).update

      if result.success?
        redirect_to hotel_room_status_board_path(current_hotel, board_params), notice: "Maintenance block updated."
      else
        redirect_to hotel_room_status_board_path(current_hotel, board_params), alert: result.error
      end
    end

    def destroy
      block = current_hotel.room_blocks.find(params[:id])
      result = Rooms::ManageBlock.new(
        hotel: current_hotel,
        user: current_user,
        block: block
      ).destroy

      if result.success?
        redirect_to hotel_room_status_board_path(current_hotel, board_params), notice: "Maintenance block removed."
      else
        redirect_to hotel_room_status_board_path(current_hotel, board_params), alert: result.error
      end
    end

    def finish
      block = current_hotel.room_blocks.find(params[:id])
      result = Rooms::ManageBlock.new(
        hotel: current_hotel,
        user: current_user,
        block: block
      ).finish

      if result.success?
        redirect_to hotel_room_status_board_path(current_hotel, board_params), notice: "Maintenance block finished."
      else
        redirect_to hotel_room_status_board_path(current_hotel, board_params), alert: result.error
      end
    end

    private

    def authorize_room_block_management!
      # Reuse the same permission as room status management
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_room_status", hotel: current_hotel)
    end

    def room_block_params
      params.require(:room_block).permit(:room_type_id, :room_number, :start_date, :end_date, :block_type, :reason, :notes)
    end

    def board_params
      params.permit(:start_date, :days, :layout).to_h
    end
  end
end
