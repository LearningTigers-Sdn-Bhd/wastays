# frozen_string_literal: true

module HotelPortal
  module StayView
    class BoardController < HotelPortal::BaseController
      def index
        @capabilities = ::StayView::BuildCapabilities.call(user: current_user, hotel: current_hotel)
        raise Pundit::NotAuthorizedError unless @capabilities.view_board?

        build_board

        if turbo_frame_request?
          render partial: "hotel_portal/stay_view/board/board", locals: { board: @board, state: @stay_view_state }, layout: false
        end
      end

      private

      def build_board
        @stay_view_state = ::StayView::BoardState.new(hotel: current_hotel, params: board_params)
        @board = ::StayView::BuildBoard.call(
          hotel: current_hotel,
          user: current_user,
          capabilities: @capabilities,
          **@stay_view_state.build_options
        )
      end

      def board_params
        params.permit(:view, :start_date, :date, :days, :density, :room_type_id, :booking_status, :occupancy, :physical_status)
      end
    end
  end
end
