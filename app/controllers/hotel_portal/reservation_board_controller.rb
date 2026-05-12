# frozen_string_literal: true

module HotelPortal
  class ReservationBoardController < BaseController
    before_action :authorize_reservation_board!

    def index
      @start_date = parse_start_date
      @board_days = parse_board_days
      @board_layout = parse_board_layout
      @board_query_params = { days: @board_days, layout: @board_layout }

      @rate_plan_names = RatePlan.joins(:room_type).where(room_types: { hotel_id: current_hotel.id }).distinct.pluck(:name)
      @selected_rate_plan_name = params.dig(:filters, :rate_plan_name) || @rate_plan_names.first

      filters_params = params[:filters].respond_to?(:to_unsafe_h) ? params[:filters].to_unsafe_h : (params[:filters] || {})
      board_filters = filters_params.symbolize_keys.merge(rate_plan_name: @selected_rate_plan_name)

      @reservation_board = Rooms::ReservationBoardBuilder.new(
        hotel: current_hotel,
        start_date: @start_date,
        days: @board_days,
        filters: board_filters
      ).call
    end

    private

    def parse_start_date
      Date.parse(params[:start_date].to_s)
    rescue ArgumentError
      Date.current
    end

    def parse_board_days
      case params[:days].to_i
      when 7, 14, 21, 30 then params[:days].to_i
      else 14
      end
    end

    def parse_board_layout
      %w[comfortable compact].include?(params[:layout]) ? params[:layout] : "comfortable"
    end

    def authorize_reservation_board!
      raise Pundit::NotAuthorizedError unless can_view_reservation_board?
    end
  end
end
