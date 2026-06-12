# frozen_string_literal: true

module HotelPortal
  module Bookings
    class BoardController < BaseController
      before_action :authorize_booking_timeline_board!

      def index
        @start_date = parse_start_date
        @board_days = parse_board_days
        @board_layout = parse_board_layout
        @board_query_params = { days: @board_days, layout: @board_layout }

        @rate_plan_names = RatePlan.joins(:room_type).where(room_types: { hotel_id: current_hotel.id }).distinct.pluck(:name)
        @selected_rate_plan_name = params.dig(:filters, :rate_plan_name) || @rate_plan_names.first
        filters = params[:filters].respond_to?(:to_unsafe_h) ? params[:filters].to_unsafe_h : (params[:filters] || {})

        @booking_timeline_board = Rooms::ReservationBoardBuilder.new(
          hotel: current_hotel,
          start_date: @start_date,
          days: @board_days,
          filters: filters.symbolize_keys.merge(rate_plan_name: @selected_rate_plan_name)
        ).call

        render "hotel_portal/bookings/board/index"
      end

      private

      def parse_start_date
        Date.parse(params[:start_date].to_s)
      rescue ArgumentError
        Date.current
      end

      def parse_board_days
        [ 7, 14, 21, 30 ].include?(params[:days].to_i) ? params[:days].to_i : 14
      end

      def parse_board_layout
        %w[comfortable compact].include?(params[:layout]) ? params[:layout] : "comfortable"
      end

      def authorize_booking_timeline_board!
        raise Pundit::NotAuthorizedError unless can_view_reservation_board?
      end
    end
  end
end
