# app/components/hotel_portal/reservation_board/toolbar_component.rb
module HotelPortal
  module ReservationBoard
    class ToolbarComponent < ViewComponent::Base
      def initialize(
        board_days:,
        board_layout:,
        start_date:,
        current_hotel:,
        comfortable_mode:,
        board_query_params:,
        nav_step_days:,
        rate_plan_names:,
        selected_rate_plan_name:
      )
        @board_days = board_days
        @board_layout = board_layout
        @start_date = start_date
        @current_hotel = current_hotel
        @comfortable_mode = comfortable_mode
        @board_query_params = board_query_params
        @nav_step_days = nav_step_days
        @rate_plan_names = rate_plan_names
        @selected_rate_plan_name = selected_rate_plan_name
      end

      private

      attr_reader :board_days, :board_layout, :start_date, :current_hotel,
                  :comfortable_mode, :board_query_params, :nav_step_days,
                  :rate_plan_names, :selected_rate_plan_name

      def common_params
        @common_params ||= board_query_params.merge(filters: params[:filters]&.to_unsafe_h)
      end
    end
  end
end
