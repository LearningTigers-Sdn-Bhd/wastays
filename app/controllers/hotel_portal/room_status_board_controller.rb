# frozen_string_literal: true

require_dependency Rails.root.join("app/presenters/hotel_portal/room_status_board_presenter").to_s

module HotelPortal
  class RoomStatusBoardController < BaseController
    before_action :authorize_room_status_board!
    before_action -> { require_feature!("room_status_board") }

    def index
      @start_date = parse_start_date
      @board_days = parse_board_days
      @board_layout = parse_board_layout
      @board_query_params = { days: @board_days, layout: @board_layout }
      @room_status_board = Rooms::RoomStatusBoardBuilder.new(hotel: current_hotel, start_date: @start_date, days: @board_days).call

      @presenter = HotelPortal::RoomStatusBoardPresenter.new(
        room_status_board: @room_status_board,
        start_date: @start_date,
        board_days: @board_days,
        board_layout: @board_layout,
        user: current_user,
        hotel: current_hotel
      )
    end

    def housekeeping_requests
      @room_number = params[:room_number]
      @housekeeping_requests = HousekeepingRequest.joins(:booking)
        .joins(booking: :booking_rooms)
        .where(bookings: { hotel_id: current_hotel.id })
        .where(booking_rooms: { room_number: @room_number })
        .where(archived_at: nil)
        .where(status: "in_progress")
        .order(created_at: :desc)

      render "hotel_portal/room_status_board/housekeeping_requests", layout: false
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
