# app/components/hotel_portal/reservation_board/legend_component.rb
module HotelPortal
  module ReservationBoard
    class LegendComponent < ViewComponent::Base
      def initialize(booking_styles:, status_icons:, reservation_board:)
        @booking_styles = booking_styles
        @status_icons = status_icons
        @reservation_board = reservation_board
      end

      private

      attr_reader :booking_styles, :status_icons, :reservation_board

      def status_list
        ["all", "not_ready"] + %w[confirmed checked_in pending]
      end

      def count_for(status)
        reservation_board[:status_counts][status]
      end

      def style_for(status)
        booking_styles.fetch(status, 'border-slate-200 bg-slate-50 text-slate-600')
      end

      def icon_for(status)
        status_icons[status]&.html_safe
      end
    end
  end
end
