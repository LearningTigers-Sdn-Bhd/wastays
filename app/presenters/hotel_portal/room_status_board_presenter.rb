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
        %w[ready dirty cleaning inspection_failed awaiting_inspection late_checkout_detected].include?(status)
      end

      def can_mark_cleaning?
        %w[dirty inspection_failed awaiting_inspection].include?(status)
      end

      def can_mark_dirty?
        %w[ready late_checkout_detected].include?(status)
      end

      def can_mark_late_checkout?
        %w[ready dirty].include?(status)
      end

      def can_mark_awaiting_inspection?
        status == "cleaning"
      end

      def can_mark_ready?
        %w[dirty cleaning inspection_failed awaiting_inspection late_checkout_detected].include?(status)
      end

      def can_fail_inspection?
        status == "awaiting_inspection"
      end

      def room_type
        room[:room_type]
      end

      def smoking_label
        room_type.smoking_allowed ? "Smoking Allowed" : "No Smoking"
      end

      def smoking_color
        room_type.smoking_allowed ? "text-emerald-500" : "text-slate-400"
      end

      def pets_label
        room_type.pets_allowed ? "Pets Allowed" : "No Pets"
      end

      def pets_color
        room_type.pets_allowed ? "text-emerald-500" : "text-slate-400"
      end

      def smoking_icon
        if room_type.smoking_allowed
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M17 12H3a1 1 0 0 0-1 1v2a1 1 0 0 0 1 1h14" /><path d="M18 8c0-2.5-2-2.5-2-5" /><path d="M21 16a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1" /><path d="M22 8c0-2.5-2-2.5-2-5" /><path d="M7 12v4" /></svg>'.html_safe
        else
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 12H3a1 1 0 0 0-1 1v2a1 1 0 0 0 1 1h13" /><path d="M18 8c0-2.5-2-2.5-2-5" /><path d="m2 2 20 20" /><path d="M21 12a1 1 0 0 1 1 1v2a1 1 0 0 1-.5.866" /><path d="M22 8c0-2.5-2-2.5-2-5" /><path d="M7 12v4" /></svg>'.html_safe
        end
      end

      def pets_icon
        if room_type.pets_allowed
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="4" r="2" /><circle cx="18" cy="8" r="2" /><circle cx="20" cy="16" r="2" /><path d="M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z" /></svg>'.html_safe
        else
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="4" r="2" /><circle cx="18" cy="8" r="2" /><circle cx="20" cy="16" r="2" /><path d="M9 10a5 5 0 0 1 5 5v3.5a3.5 3.5 0 0 1-6.84 1.045Q6.52 17.48 4.46 16.84A3.5 3.5 0 0 1 5.5 10Z" /><path d="m2 2 20 20" /></svg>'.html_safe
        end
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
      comfortable_mode? ? 160 : 130
    end

    def grid_day_width
      comfortable_mode? ? 84 : 78
    end

    def grid_template_columns
      "#{grid_room_width}px repeat(#{board_dates.size}, var(--grid-day-width, #{grid_day_width}px))"
    end

    def page_spacing
      comfortable_mode? ? "space-y-6" : "space-y-3"
    end

    def container_padding
      comfortable_mode? ? "px-4 md:px-0" : "px-2 md:px-0"
    end

    def card_padding
      comfortable_mode? ? "px-3 py-1" : "px-2.5 py-1"
    end

    def title_class
      comfortable_mode? ? "text-xl sm:text-2xl" : "text-lg sm:text-xl"
    end

    def subtitle_class
      comfortable_mode? ? "text-xs" : "text-[11px]"
    end

    def summary_padding
      comfortable_mode? ? "px-4 py-2" : "px-2 py-1.5"
    end

    def summary_gap
      comfortable_mode? ? "gap-3" : "gap-1.5"
    end

    def chip_text_class
      comfortable_mode? ? "text-[10px]" : "text-[9px]"
    end

    def room_number_class
      comfortable_mode? ? "text-lg" : "text-sm"
    end

    def row_min_base
      comfortable_mode? ? 44 : 40
    end

    def block_step
      comfortable_mode? ? 30 : 26
    end

    def block_top
      comfortable_mode? ? 5 : 4
    end

    def block_left_pad
      comfortable_mode? ? 6 : 3
    end

    def row_min_height(room)
      max_blocks_same_start = room[:blocks].group_by { |block| [ block[:check_in], visible_start_date ].max }.values.map(&:size).max || 1
      padding = comfortable_mode? ? 24 : 20
      [ row_min_base, padding + (max_blocks_same_start * block_step) ].max
    end

    def blocks_for(room, date)
      room[:blocks].select { |block| [ block[:check_in], visible_start_date ].max == date }
    end

    def maintenance_blocks_for(room, date)
      room[:maintenance_blocks].select { |block| [ block[:start_date], visible_start_date ].max == date }
    end

    def booking_count_at(room, date)
      blocks_for(room, date).size
    end

    def cell_meta(room, date)
      day_data = room[:daily_data][date]
      booking_state = day_data[:booking_state]
      physical_status = day_data[:status]

      bg_class = cell_color(booking_state)
      bg_class = cell_color(:out_of_service) if physical_status == "out_of_service"

      is_interactable = (booking_state == :none || booking_state == :completed) && physical_status != "out_of_service"

      {
        bg_class: bg_class,
        is_interactable: is_interactable
      }
    end

    def block_meta(block)
      clipped_left = block[:check_in] < visible_start_date
      clipped_right = block[:check_out] > visible_end_exclusive
      left_offset = clipped_left ? 0 : block_left_pad
      right_trim = clipped_right ? 0 : block_left_pad
      width_calc = "calc(#{block[:span]} * 100% - #{left_offset + right_trim}px)"
      clip_corner_class = [ ("rounded-l-none" if clipped_left), ("rounded-r-none" if clipped_right) ].compact.join(" ")

      {
        style_class: booking_style(block[:status]),
        left_offset: left_offset,
        width_calc: width_calc,
        clip_corner_class: clip_corner_class
      }
    end

    def maintenance_block_meta(block)
      clipped_left = block[:start_date] < visible_start_date
      clipped_right = block[:end_date] > visible_end_exclusive
      left_offset = clipped_left ? 0 : block_left_pad
      right_trim = clipped_right ? 0 : block_left_pad
      width_calc = "calc(#{block[:span]} * 100% - #{left_offset + right_trim}px)"
      clip_corner_class = [ ("rounded-l-none" if clipped_left), ("rounded-r-none" if clipped_right) ].compact.join(" ")

      {
        left_offset: left_offset,
        width_calc: width_calc,
        clip_corner_class: clip_corner_class
      }
    end

    def status_badge_meta(status, failure_note = nil)
      {
        container_class: "inline-flex items-center justify-center rounded-full border size-5 #{status_style(status)} cursor-help shadow-sm",
        tooltip_wrapper_class: "hidden z-[100] #{(status == 'inspection_failed' && failure_note.present?) ? 'px-4 py-3 rounded-2xl w-64' : 'px-3 py-1.5 rounded-full'} bg-white border border-slate-200 shadow-xl pointer-events-none",
        icon_bg_class: "p-1 rounded-full #{status_style(status, fallback: 'border-slate-400').split(' ').first.gsub('border-', 'bg-')} text-white",
        label: room_status_label(status)
      }
    end

    def room_status_label(status)
      status.present? ? status.to_s.humanize.titleize : "Unknown Status"
    end

    def status_style(status, fallback: "border-slate-200 bg-slate-50 text-slate-700")
      {
        "all" => "border-slate-300 bg-slate-100 text-slate-700",
        "ready" => "border-emerald-200 bg-emerald-50 text-emerald-700",
        "occupied" => "border-sky-200 bg-sky-50 text-sky-700",
        "dirty" => "border-orange-200 bg-orange-50 text-orange-700",
        "cleaning" => "border-blue-200 bg-blue-50 text-blue-700",
        "late_checkout_detected" => "border-amber-200 bg-amber-50 text-amber-700",
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
      when "late_checkout_detected"
        '<svg class="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5" /><path stroke-linecap="round" stroke-linejoin="round" d="M12 22a10 10 0 1 0-10-10" /></svg>'.html_safe
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
        "review_due_out" => "border-amber-200 bg-amber-50 text-amber-700",
        "completed" => "border-emerald-200 bg-emerald-50 text-emerald-700",
        "cancelled" => "border-slate-300 bg-slate-100 text-slate-600"
      }.fetch(status.to_s, "border-sky-200 bg-sky-50 text-sky-700")
    end

    def status_counts
      room_status_board[:status_counts]
    end
  end
end
