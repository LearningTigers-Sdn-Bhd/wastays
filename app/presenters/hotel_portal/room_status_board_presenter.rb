# frozen_string_literal: true

module HotelPortal
  class RoomStatusBoardPresenter
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper

    attr_reader :room_status_board, :start_date, :board_days, :board_layout, :user, :hotel

    def initialize(room_status_board:, start_date:, board_days:, board_layout:, user: nil, hotel: nil)
      @room_status_board = room_status_board
      @start_date = start_date
      @board_days = board_days
      @board_layout = board_layout
      @user = user
      @hotel = hotel
    end

    def room_row(room)
      RoomRow.new(room, user, hotel)
    end

    class RoomRow
      attr_reader :room, :user, :hotel

      def initialize(room, user, hotel)
        @room = room
        @user = user
        @hotel = hotel
      end

      def status
        @status ||= room.dig(:status, :status).to_s
      end

      def room_status_id
        room.dig(:status, :room_status_id)
      end

      def failure_note
        @failure_note ||= room.dig(:status, :notes).to_s.strip
      end

      def can_manage?
        @can_manage ||= user&.has_permission?("manage_room_status", hotel: hotel)
      end

      def has_actions?
        %w[ready dirty cleaning inspection_failed awaiting_inspection].include?(status)
      end

      def room_type
        room[:room_type]
      end
    end

    def comfortable_mode?
      @board_layout == "comfortable"
    end

    def board_dates
      room_status_board[:dates]
    end

    def room_groups
      room_status_board[:room_groups]
    end

    def visible_start_date
      board_dates.first
    end

    def visible_end_exclusive
      board_dates.last + 1.day
    end

    def board_range_end
      start_date + (board_days - 1).days
    end

    def nav_step_days
      board_days
    end

    def grid_room_width
      comfortable_mode? ? 180 : 130
    end

    def grid_day_width
      comfortable_mode? ? 84 : 64
    end

    def grid_template_columns
      "#{grid_room_width}px repeat(#{board_dates.size}, minmax(#{grid_day_width}px, 1fr))"
    end

    def page_spacing
      comfortable_mode? ? "space-y-6" : "space-y-4"
    end

    def container_padding
      comfortable_mode? ? "px-4 md:px-0" : "px-3 md:px-0"
    end

    def card_padding
      comfortable_mode? ? "px-4 py-3" : "px-3 py-2"
    end

    def title_class
      comfortable_mode? ? "text-xl sm:text-2xl" : "text-lg sm:text-xl"
    end

    def subtitle_class
      comfortable_mode? ? "text-xs" : "text-[11px]"
    end

    def summary_padding
      comfortable_mode? ? "px-4 py-3" : "px-3 py-2"
    end

    def summary_gap
      comfortable_mode? ? "gap-3" : "gap-2"
    end

    def chip_text_class
      comfortable_mode? ? "text-[10px]" : "text-[9px]"
    end

    def room_number_class
      comfortable_mode? ? "text-xl" : "text-lg"
    end

    def row_min_base
      comfortable_mode? ? 80 : 64
    end

    def block_step
      comfortable_mode? ? 48 : 40
    end

    def block_top
      comfortable_mode? ? 6 : 4
    end

    def block_left_pad
      comfortable_mode? ? 6 : 4
    end

    def row_min_height(room)
      max_blocks_same_start = room[:blocks].group_by { |block| [ block[:check_in], visible_start_date ].max }.values.map(&:size).max || 1
      [ row_min_base, 24 + (max_blocks_same_start * block_step) ].max
    end

    def status_style(status, fallback: "border-slate-200 bg-slate-50 text-slate-700")
      {
        "all" => "border-slate-300 bg-slate-100 text-slate-700",
        "ready" => "border-emerald-200 bg-emerald-50 text-emerald-700",
        "occupied" => "border-sky-200 bg-sky-50 text-sky-700",
        "dirty" => "border-orange-200 bg-orange-50 text-orange-700",
        "cleaning" => "border-blue-200 bg-blue-50 text-blue-700",
        "awaiting_inspection" => "border-indigo-200 bg-indigo-50 text-indigo-700",
        "inspection_failed" => "border-rose-200 bg-rose-50 text-rose-700",
        "out_of_service" => "border-slate-300 bg-slate-100 text-slate-700"
      }.fetch(status.to_s, fallback)
    end

    def cell_color(booking_state)
      {
        none: "bg-emerald-50", # Available (Green)
        arrival: "bg-amber-100", # Arriving (Yellow)
        occupied: "bg-rose-100", # Occupied (Red)
        completed: "bg-white", # Completed Booking (White)
        out_of_service: "bg-slate-100" # Blocked/Maintenance (Grey)
      }.fetch(booking_state, "bg-white")
    end

    def status_icon(status)
      case status.to_s
      when "ready"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" /></svg>'.html_safe
      when "occupied"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z" /></svg>'.html_safe
      when "dirty"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>'.html_safe
      when "cleaning"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z" /></svg>'.html_safe
      when "awaiting_inspection"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" /></svg>'.html_safe
      when "inspection_failed"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>'.html_safe
      when "out_of_service"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" /></svg>'.html_safe
      when "all"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25a2.25 2.25 0 01-2.25-2.25v-2.25z" /></svg>'.html_safe
      end
    end

    def booking_style(status)
      {
        "confirmed" => "border-blue-200 bg-blue-50 text-blue-700",
        "checked_in" => "border-violet-200 bg-violet-50 text-violet-700",
        "completed" => "border-emerald-200 bg-emerald-50 text-emerald-700",
        "cancelled" => "border-slate-300 bg-slate-100 text-slate-600"
      }.fetch(status.to_s, "border-sky-200 bg-sky-50 text-sky-700")
    end

    def status_counts
      room_status_board[:status_counts]
    end
  end
end
