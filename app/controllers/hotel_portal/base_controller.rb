module HotelPortal
  class BaseController < ApplicationController
    layout "hotel"
    before_action :authenticate_user!
    before_action :ensure_hotel_access!

    helper_method :locked_hotel_portal_shell?

    private

    def locked_hotel_portal_shell?
      current_hotel.present? && (current_hotel.onboarding? || current_hotel.status == "pending_review")
    end
  end
end
