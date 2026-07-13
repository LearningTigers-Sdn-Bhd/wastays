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

    def helpers
      ApplicationController.helpers
    end

    class RoomRow
      attr_reader :room, :user, :hotel

      def initialize(room, user, hotel)
        @room = room
        @user = user
        @hotel = hotel
      end

      def helpers
        ApplicationController.helpers
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

      def notes
        room.dig(:status, :notes).to_s.strip
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
          helpers.cached_icon("cigarette", stroke_width: 2.75, class: "size-3")
        else
          helpers.content_tag(:span, class: "relative inline-flex items-center justify-center size-3") do
            helpers.safe_join([
              helpers.cached_icon("cigarette", stroke_width: 2.75, class: "size-3"),
              helpers.cached_icon("ban", stroke_width: 2.75, class: "absolute size-4")
            ])
          end
        end
      end

      def pets_icon
        if room_type.pets_allowed
          helpers.cached_icon("paw-print", stroke_width: 2.75, class: "size-3")
        else
          helpers.content_tag(:span, class: "relative inline-flex items-center justify-center size-3") do
            helpers.safe_join([
              helpers.cached_icon("paw-print", stroke_width: 2.75, class: "size-3"),
              helpers.cached_icon("ban", stroke_width: 2.75, class: "absolute size-4")
            ])
          end
        end
      end

      def row_bg_class
        ""
      end

      def tooltip_header_class
        (status == "inspection_failed" && failure_note.present?) ? "mb-2" : ""
      end

      def actions_tooltip_title
        (status == "inspection_failed" && failure_note.present?) ? "Failure Reason: #{failure_note}" : ""
      end

      def cleaning_subheading_text
        if status == "inspection_failed"
          "Reclean the room before reinspection"
        elsif status == "awaiting_inspection"
          "Send back to cleaning"
        else
          "Mark as currently being cleaned"
        end
      end

      def dnd_action_icon_class
        active_dnd? ? "bg-slate-100 text-slate-500" : "bg-rose-50 text-rose-500"
      end

      def dnd_action_label
        active_dnd? ? "Remove DND" : "Do Not Disturb"
      end

      def dnd_action_subheading
        active_dnd? ? "Resume cleaning schedules" : "Flag guest requested DND today"
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
      max_extra_icons = room_groups.flat_map { |g| g[:rooms] }.map do |room|
        row = room_row(room)
        extra = 0
        extra += 1 if row.priority?
        extra += 1 if room[:housekeeping_requests]&.any?
        extra += 1 if row.active_dnd?
        extra
      end.max || 0

      base_width = comfortable_mode? ? 160 : 130
      base_width + (max_extra_icons * 18)
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

    def formatted_date_range
      "Showing #{start_date.strftime('%b %-d, %Y')} → #{board_range_end.strftime('%b %-d, %Y')} (#{board_days} days)"
    end

    def prev_start_date
      (start_date - nav_step_days.days).to_s
    end

    def next_start_date
      (start_date + nav_step_days.days).to_s
    end

    def compact_toggle_bg_class
      comfortable_mode? ? "bg-slate-200" : "bg-slate-900"
    end

    def compact_toggle_dot_class
      comfortable_mode? ? "translate-x-1" : "translate-x-3"
    end

    def filterable_statuses
      [ "all", "occupied" ] + RoomStatus::STATUSES
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

    def block_padding_class
      comfortable_mode? ? "px-3 py-1.5" : "px-1.5 py-1"
    end

    def format_block_date_range(start, finish)
      "#{start.strftime('%b %-d')} — #{finish.strftime('%b %-d, %Y')}"
    end

    def maintenance_block_update_url(block)
      maintenance_block_path(block)
    end

    def finish_maintenance_block_path(block)
      maintenance_block_path(block, finish: true)
    end

    def delete_maintenance_block_path(block)
      maintenance_block_path(block)
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
        icon_bg_class: "inline-flex items-center justify-center rounded-full border size-5 #{status_style(status, fallback: 'border-slate-400 bg-slate-400 text-slate-700')}",
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
      icon_name = case status.to_s
      when "ready" then "check"
      when "occupied" then "user"
      when "dirty" then "clock"
      when "cleaning" then "play"
      when "late_checkout_detected" then "clock"
      when "awaiting_inspection" then "magnifying-glass"
      when "inspection_failed" then "x"
      when "out_of_service" then "prohibited"
      when "all" then "squares-four"
      end

      return "" unless icon_name

      helpers.cached_icon(icon_name, library: "phosphor", variant: "light", class: "size-3")
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

    def status_count_badge(status)
      count = status_counts[status]
      return nil unless count&.positive?

      count
    end

    def occupancy_legend_items
      [
        { label: "Available", border_class: "border-emerald-200", bg_class: "bg-emerald-50", text_class: "text-emerald-700" },
        { label: "Completed Booking", border_class: "border-slate-200", bg_class: "bg-white", text_class: "text-slate-700" },
        { label: "Arriving", border_class: "border-amber-200", bg_class: "bg-amber-50", text_class: "text-amber-700" },
        { label: "Occupied", border_class: "border-rose-200", bg_class: "bg-rose-50", text_class: "text-rose-700" },
        { label: "Blocked / Maintenance", border_class: "border-slate-200", bg_class: "bg-slate-100", text_class: "text-slate-700" }
      ]
    end

    private

    def maintenance_block_path(block, finish: false)
      route_helper = finish ? :finish_hotel_room_block_path : :hotel_room_block_path
      Rails.application.routes.url_helpers.send(
        route_helper,
        hotel,
        block[:id],
        start_date: start_date,
        days: board_days,
        layout: board_layout
      )
    end
  end
end
