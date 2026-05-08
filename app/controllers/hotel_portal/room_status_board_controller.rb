# frozen_string_literal: true

module HotelPortal
  class RoomStatusBoardController < BaseController
    before_action :authorize_room_status_board!

    def index
      @start_date = parse_start_date
      @board_days = parse_board_days
      @board_layout = parse_board_layout
      @board_query_params = { days: @board_days, layout: @board_layout }
      @room_status_board = Rooms::RoomStatusBoardBuilder.new(hotel: current_hotel, start_date: @start_date, days: @board_days).call
    end

    private

    def parse_start_date
      Date.parse(params[:start_date].to_s)
    rescue ArgumentError
      Date.current
    end

    def parse_board_days
      case params[:days].to_i
      when 7, 14, 21 then params[:days].to_i
      else 14
      end
    end

    def parse_board_layout
      %w[comfortable compact].include?(params[:layout]) ? params[:layout] : "comfortable"
    end

    def authorize_room_status_board!
      raise Pundit::NotAuthorizedError unless can_view_room_status_board?
    end
  end
end
