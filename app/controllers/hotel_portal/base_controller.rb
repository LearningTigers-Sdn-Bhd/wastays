# frozen_string_literal: true

module HotelPortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "hotel"
    helper HotelPortal::SettingsNavigationHelper
    before_action :authenticate_user!
    before_action :reject_corporate_user!
    before_action :ensure_hotel_access!
    before_action :protect_pending_review_writes!

    helper_method :locked_hotel_portal_shell?

    private

    # The retired arrivals/in-house/checked-out/bookings index pages were tables,
    # so their bookmarks keep landing on the list view. An explicit ?view= still
    # wins — a caller that asked for a view should get it, not a reset.
    def legacy_view
      HotelPortal::FrontDeskController::VIEWS.include?(params[:view]) ? params[:view] : "list"
    end

    # Pages that hand a request off to another controller carry where to come
    # back to in ?redirect_to. Rails already refuses to follow that off-host, but
    # it does so by raising -- a 500 for what is really a bad parameter. Accept
    # only a path within this app, and fall back rather than fail.
    def safe_redirect_target(fallback)
      candidate = params[:redirect_to].to_s
      return fallback unless candidate.start_with?("/")
      return fallback if candidate.start_with?("//") # protocol-relative: another host

      candidate
    end

    def reject_corporate_user!
      return unless current_user&.corporate?

      redirect_to corporate_dashboard_path, alert: "Corporate users do not have hotel staff access."
    end

    def locked_hotel_portal_shell?
      current_hotel.present? && (current_hotel.onboarding? || current_hotel.status == "pending_review")
    end

    def protect_pending_review_writes!
      return if request.get? || request.head?
      return unless current_hotel&.status == "pending_review"
      return if is_a?(HotelPortal::UserProfilesController) || is_a?(HotelPortal::OnboardingSubmissionsController)

      redirect_to hotel_onboarding_section_path(current_hotel, section_key: "review"),
                  alert: "Property setup is read-only while WAStays reviews it.", status: :see_other
    end
  end
end
