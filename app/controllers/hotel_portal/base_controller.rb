# frozen_string_literal: true

module HotelPortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "hotel"
    helper HotelPortal::SettingsNavigationHelper
    before_action :authenticate_user!
    before_action :reject_corporate_user!
    before_action :ensure_hotel_access!
    before_action :enforce_setup_lock!
    before_action :protect_pending_review_writes!

    # Controllers a property still in setup can always reach. Onboarding itself is the
    # point of the lock; the rest are the things someone needs regardless of whether
    # their property is open — their own profile, and the page explaining the wait.
    # Logging out is not a hotel-portal controller, so it stays reachable for free.
    SETUP_LOCK_EXEMPT = %w[
      HotelPortal::OnboardingController
      HotelPortal::OnboardingSubmissionsController
      HotelPortal::OnboardingSessionsController
      HotelPortal::UserProfilesController
      HotelPortal::SetupLocksController
    ].freeze

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

    # A property that has not been submitted yet has nothing to run — no rates, no
    # inventory, often no rooms — so the portal around it is a maze of empty pages.
    # Send whoever can finish setup back to where they left off, and tell everyone
    # else to wait.
    #
    # Off unless the hotel opts in, so this rolls out one property at a time.
    def enforce_setup_lock!
      return unless current_hotel&.status == "setup"
      return unless current_hotel.setup_lock_enabled?
      return if current_user&.superadmin?
      return if SETUP_LOCK_EXEMPT.include?(self.class.name)

      if HotelPolicy.new(current_user, current_hotel).update?
        redirect_to hotel_onboarding_section_path(
          current_hotel, section_key: Onboarding::ResumePageResolver.new(hotel: current_hotel).call.key
        )
      else
        redirect_to hotel_setup_lock_path(current_hotel)
      end
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
