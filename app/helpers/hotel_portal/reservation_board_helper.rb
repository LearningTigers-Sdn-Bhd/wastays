# frozen_string_literal: true

module HotelPortal
  module ReservationBoardHelper
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

    def booking_block_source_badge_class(block)
      block[:source] == "internal" ? "bg-slate-200/60 text-slate-600" : "bg-blue-100 text-blue-700"
    end

    def booking_block_payment_badge_class(block)
      block[:payment_status] == "captured" ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"
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
