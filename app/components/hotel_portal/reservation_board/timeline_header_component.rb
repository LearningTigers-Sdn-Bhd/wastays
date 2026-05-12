# app/components/hotel_portal/reservation_board/timeline_header_component.rb
module HotelPortal
  module ReservationBoard
    class TimelineHeaderComponent < ViewComponent::Base
      def initialize(grid_template_columns:, card_padding:, board_dates:, summary_padding:)
        @grid_template_columns = grid_template_columns
        @card_padding = card_padding
        @board_dates = board_dates
        @summary_padding = summary_padding
      end

      private

      attr_reader :grid_template_columns, :card_padding, :board_dates, :summary_padding
    end
  end
end
