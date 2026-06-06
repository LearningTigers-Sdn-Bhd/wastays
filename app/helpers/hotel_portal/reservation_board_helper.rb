# frozen_string_literal: true

module HotelPortal
  module ReservationBoardHelper
    STATUS_ICONS = {
      "pending" => "clock",
      "confirmed" => "check-circle",
      "checked_in" => "log-in",
      "completed" => "check-check",
      "cancelled" => "x-circle",
      "no_show" => "user-x",
      "review_due_out" => "triangle-alert",
      "overbooked" => "alert-octagon",
      "not_ready" => "ban"
    }.freeze

    STATUS_ICON_CLASSES = {
      "pending" => "text-amber-600",
      "confirmed" => "text-blue-600",
      "checked_in" => "text-violet-600",
      "completed" => "text-emerald-600",
      "cancelled" => "text-slate-500",
      "no_show" => "text-rose-600",
      "review_due_out" => "text-orange-600",
      "overbooked" => "text-red-700",
      "not_ready" => "text-red-500"
    }.freeze

    def booking_status_icon(status)
      STATUS_ICONS.fetch(status.to_s, "circle")
    end

    def booking_icon_class(status)
      STATUS_ICON_CLASSES.fetch(status.to_s, "text-slate-500")
    end

    def reservation_board_row_height(room, row_min_base, block_step, visible_start_date)
      max_blocks_same_start = room[:blocks].group_by { |block| [ block[:check_in], visible_start_date ].max }.values.map(&:size).max || 1
      [ row_min_base, 24 + (max_blocks_same_start * block_step) ].max
    end

    def reservation_board_rate_for(reservation_board, room_type_id, date)
      reservation_board[:rates][[ room_type_id, date ]]
    end

    def booking_block_status_classes(block, booking_styles)
      booking_styles.fetch(block[:status].to_s, "border-sky-200 bg-sky-50 text-sky-700")
    end

    def booking_block_clip_corner_class(block, visible_start_date, visible_end_exclusive)
      clipped_left = block[:check_in] < visible_start_date
      clipped_right = block[:check_out] > visible_end_exclusive
      [ ("rounded-l-none" if clipped_left), ("rounded-r-none" if clipped_right) ].compact.join(" ")
    end

    def room_status_style_classes(status)
      case status.to_s
      when "out_of_service" then "bg-rose-50 border-rose-200 text-rose-700"
      when "cleaning" then "bg-amber-50 border-amber-200 text-amber-700"
      else "bg-slate-50 border-slate-200 text-slate-700"
      end
    end

    def legend_style_for(status, booking_styles)
      booking_styles.fetch(status, "border-slate-200 bg-slate-50 text-slate-600")
    end

    def legend_count_for(reservation_board, status)
      reservation_board[:status_counts][status] || 0
    end
  end
end
