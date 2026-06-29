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

      def priority?
        room.dig(:status, :priority) == true
      end

      def active_dnd?
        room.dig(:status, :active_dnd) == true
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
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><rect x="24" y="136" width="208" height="48" rx="8" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="88" y1="184" x2="88" y2="136" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M208,104s-18-8,0-40,0-40,0-40" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M168,104s-18-8,0-40,0-40,0-40" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
        else
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M121,136H32a8,8,0,0,0-8,8v32a8,8,0,0,0,8,8h97" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="88" y1="184" x2="88" y2="136" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M208,104s-18-8,0-40,0-40,0-40" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M168,104s-18-8,0-40,0-40,0-40" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="40" y1="40" x2="216" y2="216" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M232,156.4V144a8,8,0,0,0-8-8H167.3" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
        end
      end

      def pets_icon
        if room_type.pets_allowed
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><circle cx="212" cy="108" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="44" cy="108" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="92" cy="60" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="164" cy="60" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M128,104A36,36,0,0,0,93.43,130a43.49,43.49,0,0,1-20.67,25.9,32,32,0,0,0,27.73,57.62,72.49,72.49,0,0,1,55,0,32,32,0,0,0,27.73-57.62A43.46,43.46,0,0,1,162.57,130,36,36,0,0,0,128,104Z" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
        else
          '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><circle cx="212" cy="108" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="44" cy="108" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="92" cy="60" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="164" cy="60" r="20" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M128,104A36,36,0,0,0,93.43,130a43.49,43.49,0,0,1-20.67,25.9,32,32,0,0,0,27.73,57.62,72.49,72.49,0,0,1,55,0,32,32,0,0,0,27.73-57.62A43.46,43.46,0,0,1,162.57,130,36,36,0,0,0,128,104Z" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="40" y1="40" x2="216" y2="216" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
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
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><polyline points="40 144 96 200 224 72" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "occupied"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><circle cx="128" cy="96" r="64" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><path d="M32,216c19.37-33.47,54.55-56,96-56s76.63,22.53,96,56" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "dirty"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><circle cx="128" cy="128" r="96" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><polyline points="128 72 128 128 184 128" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "cleaning"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><path d="M72,39.88V216.12a8,8,0,0,0,12.15,6.69l144.08-88.12a7.82,7.82,0,0,0,0-13.38L84.15,33.19A8,8,0,0,0,72,39.88Z" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "late_checkout_detected"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><circle cx="128" cy="128" r="96" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><polyline points="128 72 128 128 184 128" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "awaiting_inspection"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><circle cx="112" cy="112" r="80" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="168.57" y1="168.57" x2="224" y2="224" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "inspection_failed"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><line x1="200" y1="56" x2="56" y2="200" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><line x1="200" y1="200" x2="56" y2="56" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
      when "out_of_service"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><line x1="195.88" y1="195.88" x2="60.12" y2="60.12" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><circle cx="128" cy="128" r="96" fill="none" stroke="currentColor" stroke-miterlimit="10" stroke-width="16"/></svg>'.html_safe
      when "all"
        '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 256 256"><rect width="256" height="256" fill="none"/><rect x="48" y="48" width="64" height="64" rx="8" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><rect x="144" y="48" width="64" height="64" rx="8" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><rect x="48" y="144" width="64" height="64" rx="8" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/><rect x="144" y="144" width="64" height="64" rx="8" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="16"/></svg>'.html_safe
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
