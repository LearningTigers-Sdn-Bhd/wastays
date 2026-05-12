# app/components/hotel_portal/reservation_board/room_row_component.rb
module HotelPortal
  module ReservationBoard
    class RoomRowComponent < ViewComponent::Base
      def initialize(
        room:,
        grid_template_columns:,
        row_min_base:,
        block_step:,
        card_padding:,
        room_number_class:,
        board_dates:,
        summary_padding:,
        reservation_board:,
        visible_start_date:,
        block_left_pad:,
        block_top:,
        booking_styles:,
        visible_end_exclusive:,
        booking_name_class:,
        booking_amount_class:,
        booking_badge_class:,
        booking_status_class:,
        booking_meta_class:,
        current_hotel:,
        rate_text_class:,
        currency_text_class:
      )
        @room = room
        @grid_template_columns = grid_template_columns
        @row_min_base = row_min_base
        @block_step = block_step
        @card_padding = card_padding
        @room_number_class = room_number_class
        @board_dates = board_dates
        @summary_padding = summary_padding
        @reservation_board = reservation_board
        @visible_start_date = visible_start_date
        @block_left_pad = block_left_pad
        @block_top = block_top
        @booking_styles = booking_styles
        @visible_end_exclusive = visible_end_exclusive
        @booking_name_class = booking_name_class
        @booking_amount_class = booking_amount_class
        @booking_badge_class = booking_badge_class
        @booking_status_class = booking_status_class
        @booking_meta_class = booking_meta_class
        @current_hotel = current_hotel
        @rate_text_class = rate_text_class
        @currency_text_class = currency_text_class
      end

      private

      attr_reader :room, :grid_template_columns, :row_min_base, :block_step,
                  :card_padding, :room_number_class, :board_dates, :summary_padding,
                  :reservation_board, :visible_start_date, :block_left_pad, :block_top,
                  :booking_styles, :visible_end_exclusive, :booking_name_class,
                  :booking_amount_class, :booking_badge_class, :booking_status_class,
                  :booking_meta_class, :current_hotel, :rate_text_class, :currency_text_class

      def row_min_height
        max_blocks_same_start = room[:blocks].group_by { |block| [block[:check_in], visible_start_date].max }.values.map(&:size).max || 1
        [row_min_base, 24 + (max_blocks_same_start * block_step)].max
      end

      def room_type
        room[:room_type]
      end

      def rate_for(date)
        reservation_board[:rates][[room_type.id, date]]
      end

      def occupied_on?(date)
        room[:blocks].any? { |b| b[:check_in] <= date && b[:check_out] > date }
      end

      def blocks_starting_on(date)
        room[:blocks].select { |block| [block[:check_in], visible_start_date].max == date }
      end
    end
  end
end
