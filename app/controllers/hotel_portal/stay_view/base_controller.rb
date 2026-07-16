# frozen_string_literal: true

module HotelPortal
  module StayView
    class BaseController < HotelPortal::BaseController
      include OffcanvasTransactionCompletion

      helper_method :stay_view_state

      before_action :set_stay_view_context

      private

      attr_reader :stay_view_state

      def set_stay_view_context
        fallback = hotel_stay_view_path(current_hotel)
        @return_to = offcanvas_return_to(fallback:)
        @stay_view_state = ::StayView::BoardState.new(hotel: current_hotel, params: state_source)
      end

      def state_source
        direct = params.permit(:view, :start_date, :date, :days, :room_type_id, :booking_status, :occupancy, :physical_status).to_h
        return direct if direct.present?

        query = URI.parse(@return_to).query
        query.present? ? Rack::Utils.parse_nested_query(query) : {}
      rescue URI::InvalidURIError
        {}
      end

      def capabilities
        @capabilities ||= ::StayView::BuildCapabilities.call(user: current_user, hotel: current_hotel)
      end

      def require_capability!(name)
        raise Pundit::NotAuthorizedError unless capabilities.public_send("#{name}?")
      end

      def respond_with_board(message)
        respond_to do |format|
          format.turbo_stream do
            board = ::StayView::BuildBoard.call(
              hotel: current_hotel,
              user: current_user,
              capabilities:,
              **stay_view_state.build_options
            )
            render turbo_stream: [
              turbo_stream.replace(
                "stay_view_board",
                partial: "hotel_portal/stay_view/board/board",
                locals: { board:, state: stay_view_state }
              ),
              helpers.turbo_stream_action_tag(:complete_offcanvas, target: "offcanvas_drawer"),
              toast_stream(message, type: :success)
            ]
          end
          format.html { redirect_to @return_to, notice: message, status: :see_other }
        end
      end

      def render_sheet_error(partial)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "offcanvas_drawer",
              partial: partial
            ), status: :unprocessable_content
          end
          format.html { render partial:, status: :unprocessable_content }
        end
      end

      def add_error(record, message)
        record.errors.add(:base, Array(message).to_sentence)
      end
    end
  end
end
