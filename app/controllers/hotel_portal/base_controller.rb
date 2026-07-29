# frozen_string_literal: true

module HotelPortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "hotel"
    helper HotelPortal::SettingsNavigationHelper
    before_action :authenticate_user!
    before_action :reject_corporate_user!
    before_action :ensure_hotel_access!

    helper_method :locked_hotel_portal_shell?

    private

    # The retired arrivals/in-house/checked-out/bookings index pages were tables,
    # so their bookmarks keep landing on the list view. An explicit ?view= still
    # wins — a caller that asked for a view should get it, not a reset.
    def legacy_view
      HotelPortal::FrontDeskController::VIEWS.include?(params[:view]) ? params[:view] : "list"
    end

    def reject_corporate_user!
      return unless current_user&.corporate?

      redirect_to corporate_dashboard_path, alert: "Corporate users do not have hotel staff access."
    end

    def locked_hotel_portal_shell?
      current_hotel.present? && (current_hotel.onboarding? || current_hotel.status == "pending_review")
    end
  end
end
