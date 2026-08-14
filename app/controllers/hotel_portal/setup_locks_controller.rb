# frozen_string_literal: true

module HotelPortal
  # Where staff land while setup is locked and they are not allowed to complete it.
  # Submitted properties no longer use this explainer; they open in the PMS while under review.
  class SetupLocksController < BaseController
    def show
      redirect_to hotel_dashboard_path(current_hotel) unless current_hotel.status == "setup"
    end
  end
end
