# frozen_string_literal: true

module HotelPortal
  module Bookings
    class BoardController < BaseController
      before_action :authorize_booking_timeline_board!

      def index
        @board_view_type = parse_board_view_type
        @start_date = parse_start_date
        @board_days = @board_view_type == "room" ? 1 : parse_board_days

        @room_types = current_hotel.room_types.order(:name)
        @selected_room_type_id = parse_selected_room_type_id
        @selected_room_status = params[:room_status].presence || "all"
        @board_layout = parse_board_layout

        @board_query_params = {
          days: @board_days,
          layout: @board_layout,
          view_type: @board_view_type,
          room_type_id: @selected_room_type_id,
          room_status: @selected_room_status
        }
        filters = parse_filters
        @common_params = @board_query_params.merge(filters: filters.presence).compact

        @rate_plan_names = fetch_rate_plan_names
        @selected_rate_plan_name = params.dig(:filters, :rate_plan_name) || @rate_plan_names.first

        @booking_timeline_board = build_booking_timeline_board(filters)

        filter_board_by_room_type!(@booking_timeline_board, @selected_room_type_id)
        if @board_view_type == "room"
          filter_board_by_room_status!(@booking_timeline_board, @selected_room_status)
        end

        @presenter = HotelPortal::BookingTimelineBoardPresenter.new(
          booking_timeline_board: @booking_timeline_board,
          board_layout: @board_layout,
          board_days: @board_days,
          start_date: @start_date,
          current_user: current_user,
          current_hotel: current_hotel
        )

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

      def parse_board_view_type
        %w[stay room].include?(params[:view_type]) ? params[:view_type] : "stay"
      end

      def parse_selected_room_type_id
        selected_id = params[:room_type_id].presence
        if @board_view_type == "room" && selected_id.blank?
          @room_types.first&.id&.to_s
        else
          selected_id
        end
      end

      def parse_filters
        params[:filters].respond_to?(:to_unsafe_h) ? params[:filters].to_unsafe_h : (params[:filters] || {})
      end

      def fetch_rate_plan_names
        RatePlan.joins(:room_type).where(room_types: { hotel_id: current_hotel.id }).distinct.pluck(:name)
      end

      def build_booking_timeline_board(filters)
        Rooms::ReservationBoardBuilder.new(
          hotel: current_hotel,
          start_date: @start_date,
          days: @board_days,
          filters: filters.symbolize_keys.merge(rate_plan_name: @selected_rate_plan_name)
        ).call
      end

      def filter_board_by_room_type!(board, selected_room_type_id)
        return if selected_room_type_id.blank?

        board[:room_groups].select! { |g| g[:room_type].id.to_s == selected_room_type_id.to_s }
      end

      def filter_board_by_room_status!(board, selected_room_status)
        return if selected_room_status == "all"

        board[:room_groups].each do |group|
          group[:rooms].select! do |room|
            current_status = room_current_status(room)
            room_matches_status?(current_status, selected_room_status)
          end
        end
      end

      def room_current_status(room)
        bookings = room[:blocks].select { |b| b[:type] == "booking" }
        status_blocks = room[:blocks].select { |b| b[:type] == "room_status" }

        if status_blocks.any?
          "not_ready"
        elsif bookings.any?
          bookings.first[:status].to_s
        else
          "available"
        end
      end

      def room_matches_status?(current_status, selected_status)
        case selected_status
        when "available"
          current_status == "available"
        when "checked_in"
          current_status.in?(%w[checked_in review_due_out checkout_required])
        when "confirmed"
          current_status.in?(%w[confirmed pending])
        when "not_ready"
          current_status == "not_ready"
        else
          current_status == selected_status
        end
      end

      def authorize_booking_timeline_board!
        raise Pundit::NotAuthorizedError unless can_view_reservation_board?
      end
    end
  end
end
