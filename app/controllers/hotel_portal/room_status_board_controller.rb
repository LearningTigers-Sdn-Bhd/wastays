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

      if params[:tab] == "housekeeping"
        @staff_members = current_hotel.users.joins(:roles).where(roles: { slug: "housekeeper" }).order(:name).distinct
        @staff_members = current_hotel.users.order(:name) if @staff_members.empty?

        # Build room groups with resolved statuses, active bookings, and tasks
        @room_groups = current_hotel.room_types.order(:name).map do |room_type|
          rooms_list = room_type.room_numbers.map do |room_number|
            resolved = Rooms::StatusResolver.new(
              hotel: current_hotel,
              room_type: room_type,
              room_number: room_number,
              date: Date.current
            ).call

            active_booking = resolved.booking_details&.dig(:active)&.first || resolved.booking_details&.dig(:completed)&.first

            hk_request = HousekeepingRequest.joins(:booking)
                                            .where(bookings: { hotel_id: current_hotel.id }, room_number: room_number, status: "in_progress")
                                            .first

            {
              room_number: room_number,
              room_type: room_type,
              resolved_status: resolved.status,
              active_booking: active_booking,
              hk_request: hk_request
            }
          end

          {
            room_type: room_type,
            rooms: rooms_list
          }
        end

        # Filter by room number
        if params[:room_number].present?
          @room_groups.each do |group|
            group[:rooms].select! { |r| r[:room_number].to_s == params[:room_number].to_s }
          end
          @room_groups.select! { |group| group[:rooms].any? }
        end

        # Filter by search query
        if params[:q].present?
          q = params[:q].downcase
          @room_groups.each do |group|
            group[:rooms].select! do |r|
              r[:room_number].to_s.downcase.include?(q) ||
                group[:room_type].name.downcase.include?(q) ||
                (r[:active_booking] && (r[:active_booking].guest_name.to_s.downcase.include?(q) || r[:active_booking].confirmation_token.to_s.downcase.include?(q))) ||
                (r[:hk_request] && r[:hk_request].request_details.to_s.downcase.include?(q))
            end
          end
          @room_groups.select! { |group| group[:rooms].any? }
        end
      end
    end

    def housekeeping_requests
      @room_number = params[:room_number]
      @room_status = current_hotel.room_statuses.find_by(room_number: @room_number)
      @housekeeping_requests = HotelPortal::HousekeepingRequestsQuery.new(
        hotel: current_hotel,
        room_number: @room_number
      ).call

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
