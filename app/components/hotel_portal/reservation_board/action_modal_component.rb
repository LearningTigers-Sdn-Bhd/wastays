# app/components/hotel_portal/reservation_board/action_modal_component.rb
module HotelPortal
  module ReservationBoard
    class ActionModalComponent < ViewComponent::Base
      def initialize(current_hotel:)
        @current_hotel = current_hotel
      end

      private

      attr_reader :current_hotel
    end
  end
end
