# frozen_string_literal: true

module HotelPortal
  module StayView
    class BaseController < HotelPortal::BaseController
      helper_method :stay_view_state

      before_action :set_stay_view_context

      private

      attr_reader :stay_view_state

      def set_stay_view_context
        fallback = hotel_stay_view_path(current_hotel)
        @return_to = stay_view_return_to(fallback:)
        @stay_view_state = ::StayView::BoardState.new(hotel: current_hotel, params: state_source)
      end

      def stay_view_return_to(fallback:)
        candidate = params[:return_to].presence
        return fallback if candidate.blank?

        uri = URI.parse(candidate)
        if uri.host.present? || uri.scheme.present?
          return fallback unless "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}" == request.base_url

          uri = URI.parse(uri.request_uri)
        end

        return fallback if uri.path.blank?
        return fallback unless uri.path.start_with?("/hotel/#{current_hotel.to_param}/")

        uri.to_s
      rescue URI::InvalidURIError
        fallback
      end

      def state_source
        direct = params.permit(
          :view, :start_date, :date, :days, :room_type_id, :rate_plan_id, :occupancy, :physical_status, :room_state,
          :group_by, :room_group_id
        ).to_h
        # Nested room-operation routes also use :room_type_id as a resource key.
        # Do not accidentally reinterpret that path segment as a board filter;
        # the canonical filter value remains available through return_to.
        direct.delete("room_type_id") if request.path_parameters.key?(:room_type_id)

        query = URI.parse(@return_to).query
        returned = query.present? ? Rack::Utils.parse_nested_query(query) : {}
        returned.merge(direct)
      rescue URI::InvalidURIError
        direct
      end

      def capabilities
        @capabilities ||= ::StayView::BuildCapabilities.call(user: current_user, hotel: current_hotel)
      end

      def require_capability!(name)
        raise Pundit::NotAuthorizedError unless capabilities.public_send("#{name}?")
      end

      def require_any_capability!(*names)
        raise Pundit::NotAuthorizedError unless names.any? { |name| capabilities.public_send("#{name}?") }
      end

      def respond_with_board(message, affected_room_keys: [])
        respond_to do |format|
          format.turbo_stream do
            board = ::StayView::BuildBoard.call(
              hotel: current_hotel,
              user: current_user,
              capabilities:,
              **stay_view_state.build_options
            )
            @stay_view_state = stay_view_state.with_filters(board.filters)
            render turbo_stream: board_streams(board, message, affected_room_keys)
          end
          format.html { redirect_to @return_to, notice: message, status: :see_other }
        end
      end

      def render_sheet_error(partial)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              requesting_sheet_frame,
              partial: partial
            ), status: :unprocessable_content
          end
          format.html { render partial:, status: :unprocessable_content }
        end
      end

      def add_error(record, message)
        record.errors.add(:base, Array(message).to_sentence)
      end

      def find_housekeeping_request!(id)
        HousekeepingRequest.includes(booking: :booking_rooms)
          .left_joins(:booking)
          .where(archived_at: nil, status: %w[new assigned in_progress])
          .where("housekeeping_requests.hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: current_hotel.id)
          .find(id)
      end

      def housekeeping_room_key(housekeeping_request)
        booking_room = housekeeping_request.booking&.booking_rooms&.first
        room_number = housekeeping_request.room_number.presence || booking_room&.room_number
        room_type_id = housekeeping_request.room_type_id || booking_room&.room_type_id
        raise ActiveRecord::RecordNotFound if room_number.blank? || room_type_id.blank?

        room_type = current_hotel.room_types.find(room_type_id)
        raise ActiveRecord::RecordNotFound unless room_type.room_numbers.map(&:to_s).include?(room_number.to_s)

        "#{room_type.id}:#{room_number}"
      end

      def board_streams(board, message, affected_room_keys)
        streams = selective_timeline_streams(board, affected_room_keys)
        streams ||= [
          turbo_stream.replace(
            "stay_view_board",
            partial: "hotel_portal/stay_view/board/board",
            locals: { board:, state: stay_view_state }
          )
        ]
        streams + [
          toast_stream(message, type: :success),
          helpers.turbo_stream_action_tag(:complete_sheet, target: requesting_sheet_frame)
        ]
      end

      def requesting_sheet_frame
        turbo_frame_request_id.presence || "booking_action_sheet"
      end

      def selective_timeline_streams(board, affected_room_keys)
        return unless board.view_mode == :timeline
        return unless board.filters.to_h.compact.empty?

        keys = affected_room_keys.compact.map(&:to_s).uniq
        return if keys.empty?

        rooms = board.room_groups.flat_map(&:rooms).index_by(&:key).values_at(*keys)
        return if rooms.any?(&:nil?)

        [
          turbo_stream.replace(
            "stay_view_toolbar",
            partial: "hotel_portal/stay_view/board/toolbar",
            locals: { board:, state: stay_view_state }
          ),
          *rooms.map do |room|
            turbo_stream.replace(
              room.dom_id,
              html: view_context.render(HotelPortal::StayView::TimelineRow.new(room:, state: stay_view_state))
            )
          end
        ]
      end
    end
  end
end
