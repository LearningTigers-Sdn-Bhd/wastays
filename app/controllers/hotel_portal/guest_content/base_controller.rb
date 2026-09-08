# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Every Guest Content page runs on the same hotel, the same permission, and
    # the same page frame. The frame lives in the layout so no page repeats it.
    class BaseController < HotelPortal::SettingsBaseController
      layout "hotel_guest_content"

      before_action :set_hotel
      before_action :authorize_hotel

      private

      def set_hotel
        @hotel = current_hotel
      end

      def authorize_hotel
        authorize @hotel, :update?, policy_class: HotelPolicy
      end
    end
  end
end
