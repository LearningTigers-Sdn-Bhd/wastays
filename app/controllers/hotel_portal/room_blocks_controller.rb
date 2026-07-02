# frozen_string_literal: true

module HotelPortal
  class RoomBlocksController < BaseController
    include OffcanvasTransactionCompletion

    before_action :authorize_room_block_management!

    def new
      @room_block = current_hotel.room_blocks.build(
        room_number: params[:room_number],
        room_type_id: params[:room_type_id],
        start_date: params[:start_date].presence || Date.current,
        end_date: params[:start_date].presence || Date.current
      )
      @room_type = current_hotel.room_types.find(params[:room_type_id])
      render "form", layout: false
    end

    def edit
      @room_block = current_hotel.room_blocks.find(params[:id])
      @room_type = @room_block.room_type
      render "form", layout: false
    end

    def create
      result = Rooms::ManageBlock.new(
        hotel: current_hotel,
        user: current_user,
        params: room_block_params
      ).create

      if result.success?
        offcanvas_transaction_response(
          destination: hotel_room_status_board_path(current_hotel, board_params),
          notice: "Room blocked for maintenance."
        )
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
        offcanvas_transaction_response(
          destination: hotel_room_status_board_path(current_hotel, board_params),
          notice: "Maintenance block updated."
        )
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
        offcanvas_transaction_response(
          destination: hotel_room_status_board_path(current_hotel, board_params),
          notice: "Maintenance block removed."
        )
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
        offcanvas_transaction_response(
          destination: hotel_room_status_board_path(current_hotel, board_params),
          notice: "Maintenance block finished."
        )
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
