# frozen_string_literal: true

module HotelPortal
  class RoomStatusBoardController < BaseController
    before_action :authorize_room_status_board!

    def index
      @start_date = parse_start_date
      @room_status_board = Rooms::RoomStatusBoardBuilder.new(hotel: current_hotel, start_date: @start_date, days: 14).call
    end

    private

    def parse_start_date
      Date.parse(params[:start_date].to_s)
    rescue ArgumentError
      Date.current
    end

    def authorize_room_status_board!
      raise Pundit::NotAuthorizedError unless can_view_room_status_board?
    end
  end
end
