# app/components/hotel_portal/reservation_board/room_status_block_component.rb
module HotelPortal
  module ReservationBoard
    class RoomStatusBlockComponent < ViewComponent::Base
      def initialize(
        block:,
        block_index:,
        visible_start_date:,
        visible_end_exclusive:,
        block_left_pad:,
        block_top:,
        block_step:,
        booking_amount_class:,
        booking_status_class:
      )
        @block = block
        @block_index = block_index
        @visible_start_date = visible_start_date
        @visible_end_exclusive = visible_end_exclusive
        @block_left_pad = block_left_pad
        @block_top = block_top
        @block_step = block_step
        @booking_amount_class = booking_amount_class
        @booking_status_class = booking_status_class
      end

      private

      attr_reader :block, :block_index, :visible_start_date, :visible_end_exclusive,
                  :block_left_pad, :block_top, :block_step, :booking_amount_class,
                  :booking_status_class

      def clipped_left?
        block[:check_in] < visible_start_date
      end

      def clipped_right?
        block[:check_out] > visible_end_exclusive
      end

      def left_offset
        clipped_left? ? 0 : block_left_pad
      end

      def right_trim
        clipped_right? ? 0 : block_left_pad
      end

      def width_calc
        "calc(#{block[:span]} * 100% - #{left_offset + right_trim}px)"
      end

      def top_offset
        block_top + (block_index * block_step)
      end

      def clip_corner_class
        [ ("rounded-l-none" if clipped_left?), ("rounded-r-none" if clipped_right?) ].compact.join(" ")
      end
    end
  end
end
