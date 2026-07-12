# frozen_string_literal: true

module HotelPortal
  module BookingTimelineBoardHelper
    STATUS_ICONS = {
      "pending" => "clock",
      "confirmed" => "circle-check",
      "review_no_show" => "triangle-alert",
      "checked_in" => "log-in",
      "completed" => "check-check",
      "cancelled" => "circle-x",
      "no_show" => "user-x",
      "review_due_out" => "triangle-alert",
      "checkout_required" => "log-out",
      "overbooked" => "octagon-alert",
      "not_ready" => "ban",
      "available" => "circle-check"
    }.freeze

    STATUS_ICON_CLASSES = {
      "pending" => "text-orange-600",
      "confirmed" => "text-blue-600",
      "review_no_show" => "text-amber-600",
      "checked_in" => "text-purple-600",
      "completed" => "text-emerald-600",
      "cancelled" => "text-muted-foreground",
      "no_show" => "text-foreground",
      "review_due_out" => "text-amber-900",
      "checkout_required" => "text-orange-700",
      "overbooked" => "text-red-700",
      "not_ready" => "text-red-600",
      "available" => "text-green-600"
    }.freeze

    BOOKING_STYLES = {
      "pending" => "border-orange-200 bg-orange-50 text-orange-700",
      "confirmed" => "border-blue-200 bg-blue-50 text-blue-700",
      "review_no_show" => "border-amber-200 bg-amber-50 text-amber-800",
      "checked_in" => "border-purple-200 bg-purple-50 text-purple-700",
      "review_due_out" => "border-amber-900/20 bg-amber-50/30 text-amber-900",
      "checkout_required" => "border-orange-300 bg-orange-50/50 text-orange-800",
      "completed" => "border-emerald-200 bg-emerald-50 text-emerald-700",
      "cancelled" => "border-border-interactive bg-muted text-muted-foreground",
      "no_show" => "border-border-interactive bg-muted text-foreground",
      "not_ready" => "border-red-200 bg-red-50 text-red-700",
      "available" => "border-green-200 bg-green-50 text-green-700"
    }.freeze

    def booking_status_icon(status)
      STATUS_ICONS.fetch(status.to_s, "circle")
    end

    def booking_icon_class(status)
      STATUS_ICON_CLASSES.fetch(status.to_s, "text-muted-foreground")
    end

    def booking_timeline_board_row_height(room, row_min_base, block_step, visible_start_date)
      max_blocks_same_start = room[:blocks].group_by { |block| [ block[:check_in], visible_start_date ].max }.values.map(&:size).max || 1
      [ row_min_base, 24 + (max_blocks_same_start * block_step) ].max
    end

    def booking_timeline_board_rate_for(booking_timeline_board, room_type_id, date)
      booking_timeline_board[:rates][[ room_type_id, date ]]
    end

    def booking_block_status_classes(block)
      BOOKING_STYLES.fetch(block[:status].to_s, "border-sky-200 bg-sky-50 text-sky-700")
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
      else "bg-muted border-border text-foreground"
      end
    end

    def legend_style_for(status)
      BOOKING_STYLES.fetch(status, "border-border bg-muted text-muted-foreground")
    end

    def legend_count_for(booking_timeline_board, status)
      if status == "available"
        booking_timeline_board[:room_groups].sum do |group|
          group[:rooms].count { |room| room[:blocks].empty? }
        end
      else
        booking_timeline_board[:status_counts][status] || 0
      end
    end

    def layout_toggle_label(comfortable_mode)
      comfortable_mode ? "Compact Mode" : "Comfortable Mode"
    end

    def layout_toggle_bg_class(comfortable_mode)
      comfortable_mode ? "bg-muted" : "bg-primary"
    end

    def layout_toggle_span_class(comfortable_mode)
      comfortable_mode ? "translate-x-1" : "translate-x-3"
    end

    def room_occupied_on?(room, date)
      room[:blocks].any? { |b| b[:check_in] <= date && b[:check_out] > date }
    end

    def room_smoking_label(room_type)
      room_type.smoking_allowed ? "Smoking Allowed" : "No Smoking"
    end

    def room_smoking_color_class(room_type)
      room_type.smoking_allowed ? "text-emerald-500" : "text-muted-foreground"
    end

    def room_pets_label(room_type)
      room_type.pets_allowed ? "Pets Allowed" : "No Pets"
    end

    def room_pets_color_class(room_type)
      room_type.pets_allowed ? "text-emerald-500" : "text-muted-foreground"
    end

    def board_cell_bg_class(date)
      date == Date.current ? "bg-slate-50/50" : "bg-white"
    end

    def board_cell_drag_data_action(can_manage)
      return unless can_manage

      "dragover->booking-timeline#onDragOver dragleave->booking-timeline#onDragLeave drop->booking-timeline#onDrop"
    end

    def board_cell_action_items(date, hotel_today, current_hotel, slot_params)
      if date < hotel_today
        [ { path: hotel_booking_transaction_backdated_check_in_path(current_hotel, slot_params),
           icon: "history", icon_color: "text-amber-600", label: "Backdated Check-in" } ]
      elsif date == hotel_today
        [ { path: hotel_booking_transaction_walk_in_check_in_path(current_hotel, slot_params),
           icon: "log-in", icon_color: "text-emerald-600", label: "Walk-in Check-in" },
         { path: hotel_booking_transaction_new_booking_path(current_hotel, slot_params),
           icon: "calendar-plus", icon_color: "text-blue-600", label: "Add Booking" } ]
      else
        [ { path: hotel_booking_transaction_new_booking_path(current_hotel, slot_params),
           icon: "calendar-plus", icon_color: "text-blue-600", label: "Add Booking" } ]
      end
    end

    def board_visible_blocks_for_date(room, date, visible_start_date)
      room[:blocks].select { |block| [ block[:check_in], visible_start_date ].max == date }
    end

    def room_card_top_bar_class(room)
      bookings = room_card_bookings(room)
      status_blocks = room_card_status_blocks(room)

      if status_blocks.any?
        "bg-red-500"
      elsif bookings.any?
        case bookings.first[:status].to_s
        when "pending" then "bg-orange-500"
        when "confirmed" then "bg-blue-500"
        when "checked_in" then "bg-purple-500"
        when "review_no_show" then "bg-amber-500"
        when "review_due_out" then "bg-amber-900"
        when "checkout_required" then "bg-orange-700"
        when "completed" then "bg-emerald-500"
        when "no_show" then "bg-primary"
        else "bg-muted"
        end
      else
        "bg-green-500"
      end
    end

    def room_card_bookings(room)
      room_blocks_by_type(room, :booking)
    end

    def room_card_status_blocks(room)
      room_blocks_by_type(room, :room_status)
    end

    def room_blocks_by_type(room, type)
      room[:blocks].select { |b| b[:type] == type.to_s }
    end

    def room_card_checking_out_booking(room)
      room_card_bookings(room).find { |b| b[:status].in?(%w[checked_in review_due_out checkout_required]) }
    end

    def room_card_smoking_badge_color_class(room_type)
      room_type.smoking_allowed ? "text-emerald-500" : "text-muted-foreground"
    end

    def room_card_pets_badge_color_class(room_type)
      room_type.pets_allowed ? "text-emerald-500" : "text-muted-foreground"
    end

    def room_card_checkout_badge(booking, visible_start_date)
      days_left = (booking[:check_out].to_date - visible_start_date).to_i

      if days_left < 0
        [ "text-rose-600 bg-rose-50 border-rose-100", "Overdue" ]
      elsif days_left == 0
        [ "text-rose-600 bg-rose-50 border-rose-100", "Checkout today" ]
      elsif days_left == 1
        [ "text-amber-700 bg-amber-50 border-amber-100", "1 day left" ]
      else
        [ "text-amber-700 bg-amber-50 border-amber-100", "#{days_left} days left" ]
      end
    end

    def currency_symbol(currency)
      currency.to_s == "MYR" ? "RM" : currency.to_s
    end

    def booking_payment_status_class(payment_status)
      payment_status.to_s == "captured" ? "text-emerald-400" : "text-amber-400"
    end

    def booking_source_name(block)
      block[:source].presence || "Direct"
    end

    def booking_block_rounded_class(view_type)
      view_type.to_s == "room" ? "rounded-xl shadow-sm" : "rounded-sm"
    end

    def booking_block_classes(block, view_type, visible_start_date, visible_end_exclusive)
      "absolute z-10 overflow-hidden #{booking_block_rounded_class(view_type)} border cursor-pointer #{booking_block_status_classes(block)} #{booking_block_clip_corner_class(block, visible_start_date, visible_end_exclusive)} transition-shadow hover:shadow-md focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-1"
    end

    def booking_block_style_attributes(block, visible_start_date, visible_end_exclusive, block_left_pad, block_top, block_index, block_step)
      clipped_left = block[:check_in] < visible_start_date
      clipped_right = block[:check_out] > visible_end_exclusive
      left_offset = clipped_left ? 0 : block_left_pad
      right_trim = clipped_right ? 0 : block_left_pad
      width_calc = "calc(#{block[:span]} * 100% - #{left_offset + right_trim}px)"
      top_offset = block_top + (block_index * block_step)
      block_height = 40

      "top: #{top_offset}px; left: #{left_offset}px; width: #{width_calc}; min-width: 40px; height: #{block_height}px;"
    end

    def booking_block_accessibility_label(block)
      "#{block[:guest_name]}, #{block[:status].to_s.humanize}, room #{block[:room_number]}, #{block[:check_in].strftime('%B %-d')} to #{block[:check_out].strftime('%B %-d, %Y')}"
    end

    def booking_clipped_left?(block, visible_start_date)
      block[:check_in] < visible_start_date
    end

    def booking_clipped_right?(block, visible_end_exclusive)
      block[:check_out] > visible_end_exclusive
    end

    def comfortable_mode_styles(comfortable_mode)
      {
        page_spacing: comfortable_mode ? "space-y-6" : "space-y-4",
        container_padding: comfortable_mode ? "px-4 md:px-0" : "px-3 md:px-0",
        card_padding: comfortable_mode ? "px-4 py-1.5" : "px-3 py-1",
        summary_padding: comfortable_mode ? "px-4 py-3" : "px-3 py-2",
        room_number_class: comfortable_mode ? "text-xl" : "text-base",
        rate_text_class: comfortable_mode ? "text-[13px]" : "text-[11px]",
        currency_text_class: comfortable_mode ? "text-[11px]" : "text-[9px]",
        block_left_pad: comfortable_mode ? 6 : 4
      }
    end

    def board_grid_template_columns(comfortable_mode, board_dates_size)
      grid_room_width = comfortable_mode ? 240 : 180
      grid_day_width = comfortable_mode ? 84 : 64
      "#{grid_room_width}px repeat(#{board_dates_size}, minmax(#{grid_day_width}px, 1fr))"
    end

    def board_date_range_label(view_type, start_date, board_days)
      if view_type.to_s == "room"
        "Showing #{start_date.strftime('%b %-d, %Y')} (1 day)"
      else
        range_end = start_date + (board_days - 1).days
        "Showing #{start_date.strftime('%b %-d, %Y')} → #{range_end.strftime('%b %-d, %Y')} (#{board_days} days)"
      end
    end

    def board_view_label(view_type)
      view_type.to_s == "stay" ? "Stay View" : "Room View"
    end

    def board_view_icon(view_type)
      view_type.to_s == "stay" ? "calendar-days" : "layout-grid"
    end

    def room_card_booking_stay_dates(block)
      "#{block[:check_in].strftime('%b %-d')} → #{block[:check_out].strftime('%b %-d')}"
    end

    def room_card_booking_adults_title(booking)
      pluralize(booking.adults, "Adult")
    end

    def room_card_booking_children_title(booking)
      pluralize(booking.children.to_i, "Child")
    end

    def booking_block_margin_classes(can_manage_bookings, clipped_left, clipped_right)
      classes = []
      classes << "ml-4" if can_manage_bookings || !clipped_left
      classes << "mr-4" if can_manage_bookings || !clipped_right
      classes.join(" ")
    end

    def booking_block_status_label(block)
      block[:status].to_s.humanize
    end

    def booking_block_dates_label(block)
      "#{block[:check_in].strftime('%b %-d')} → #{block[:check_out].strftime('%b %-d, %Y')}"
    end

    def room_card_action_items(date, hotel_today, current_hotel, slot_params)
      if date < hotel_today
        [ { path: hotel_booking_transaction_backdated_check_in_path(current_hotel, slot_params),
           icon: "history", icon_color: "text-amber-600", label: "Backdated" } ]
      elsif date == hotel_today
        [ { path: hotel_booking_transaction_new_booking_path(current_hotel, slot_params),
           icon: "plus", icon_color: "text-slate-500", label: "Book" },
         { path: hotel_booking_transaction_walk_in_check_in_path(current_hotel, slot_params),
           icon: "user-check", icon_color: "text-slate-500", label: "Walk-in" } ]
      else
        [ { path: hotel_booking_transaction_new_booking_path(current_hotel, slot_params),
           icon: "plus", icon_color: "text-slate-500", label: "Book" } ]
      end
    end

    def booking_block_payment_status_label(block)
      block[:payment_status].to_s.humanize
    end
  end
end
