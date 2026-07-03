# frozen_string_literal: true

module HotelPortal
  class BookingTimelineBoardPresenter
    attr_reader :booking_timeline_board, :board_layout, :board_days, :start_date, :current_user, :current_hotel

    def initialize(booking_timeline_board:, board_layout:, board_days:, start_date:, current_user:, current_hotel:)
      @booking_timeline_board = booking_timeline_board
      @board_layout = board_layout
      @board_days = board_days
      @start_date = start_date
      @current_user = current_user
      @current_hotel = current_hotel
    end

    def comfortable_mode?
      @board_layout == "comfortable"
    end

    def board_dates
      @booking_timeline_board[:dates]
    end

    def board_groups
      @booking_timeline_board[:room_groups]
    end

    def visible_start_date
      board_dates.first
    end

    def visible_end_exclusive
      board_dates.last + 1.day
    end

    def nav_step_days
      @board_days
    end

    def page_spacing
      comfortable_mode? ? "space-y-6" : "space-y-4"
    end

    def container_padding
      comfortable_mode? ? "px-4 md:px-0" : "px-3 md:px-0"
    end

    def card_padding
      comfortable_mode? ? "px-4 py-1.5" : "px-3 py-1"
    end

    def summary_padding
      comfortable_mode? ? "px-4 py-3" : "px-3 py-2"
    end

    def room_number_class
      comfortable_mode? ? "text-xl" : "text-base"
    end

    def rate_text_class
      comfortable_mode? ? "text-[13px]" : "text-[11px]"
    end

    def currency_text_class
      comfortable_mode? ? "text-[11px]" : "text-[9px]"
    end

    def block_left_pad
      comfortable_mode? ? 6 : 4
    end

    def row_min_base
      40
    end

    def block_step
      0
    end

    def block_top
      0
    end

    def grid_template_columns
      grid_room_width = comfortable_mode? ? 240 : 180
      grid_day_width = comfortable_mode? ? 84 : 64
      "#{grid_room_width}px repeat(#{board_dates.size}, minmax(#{grid_day_width}px, 1fr))"
    end

    def can_manage_bookings?
      @current_user.has_permission?("manage_bookings", hotel: @current_hotel)
    end

    def hotel_today
      Time.current.in_time_zone(@current_hotel.hotel_time_zone).to_date
    end
  end
end
