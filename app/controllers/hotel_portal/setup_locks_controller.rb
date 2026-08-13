# frozen_string_literal: true

module HotelPortal
  # Where staff land when their property is not live yet and they are not the one
  # setting it up. Normally unreachable: invitations only go out once a property is
  # approved, so this catches accounts that predate that rule.
  class SetupLocksController < BaseController
    def show
      redirect_to hotel_dashboard_path(current_hotel) unless current_hotel.status.in?(%w[setup pending_review])
    end
  end
end
