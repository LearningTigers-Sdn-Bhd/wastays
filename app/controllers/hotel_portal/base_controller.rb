# frozen_string_literal: true

module HotelPortal
  class BaseController < ApplicationController
    include Breadcrumbable

    layout "hotel"
    helper HotelPortal::SettingsNavigationHelper
    before_action :authenticate_user!
    before_action :reject_corporate_user!
    before_action :ensure_hotel_access!
    before_action :enforce_onboarding_lock!
    before_action :protect_training_writes!

    # Controllers a property that is not live yet can always reach. Onboarding itself is
    # the point of the lock; the rest are the things someone needs regardless of whether
    # their property is open — their own profile, and the page explaining the wait.
    # Logging out is not a hotel-portal controller, so it stays reachable for free.
    ONBOARDING_LOCK_EXEMPT = %w[
      HotelPortal::OnboardingController
      HotelPortal::OnboardingSubmissionsController
      HotelPortal::OnboardingSessionsController
      HotelPortal::UserProfilesController
      HotelPortal::SetupLocksController
    ].freeze

    # Pending-review access is deliberately default-deny for writes. Adding a new
    # hotel-portal mutation must not silently make it available during training;
    # it belongs here only when the activity is safe to discard before launch.
    TRAINING_WRITE_ACTIONS = {
      "HotelPortal::BookingsController" => %w[update],
      "HotelPortal::Bookings::MovesController" => %w[update],
      "HotelPortal::Bookings::GuestRegistrationCardsController" => %w[update destroy],
      "HotelPortal::Bookings::HousekeepingRequestsController" => %w[complete],
      "HotelPortal::Bookings::ComplaintRequestsController" => %w[resolve],
      "HotelPortal::Bookings::WorkspaceActionsController" => %w[
        update_room_rate add_billing_party update_billing_terms archive_billing_party
        complete_housekeeping_request resolve_complaint_request
      ],
      "HotelPortal::Bookings::WorkspacesController" => %w[update],
      "HotelPortal::Bookings::Actions::NewBookingsController" => %w[show],
      "HotelPortal::Bookings::Actions::QuickBookingsController" => %w[show],
      "HotelPortal::Bookings::Actions::WalkInCheckInsController" => %w[show],
      "HotelPortal::Bookings::Actions::BackdatedCheckInsController" => %w[show],
      "HotelPortal::Bookings::Actions::BookingDatesController" => %w[show],
      "HotelPortal::Bookings::Actions::RoomAssignmentsController" => %w[show],
      "HotelPortal::Bookings::Actions::CheckInsController" => %w[show],
      "HotelPortal::Bookings::Actions::CheckoutsController" => %w[show],
      "HotelPortal::Bookings::Actions::CancellationsController" => %w[show],
      "HotelPortal::Bookings::Actions::VoidsController" => %w[show],
      "HotelPortal::Bookings::Actions::NoShowsController" => %w[show],
      "HotelPortal::Bookings::Actions::UndoCheckInsController" => %w[show],
      "HotelPortal::Bookings::Actions::ReinstatementsController" => %w[show],
      "HotelPortal::Bookings::Actions::LateCheckoutsController" => %w[show],
      "HotelPortal::Bookings::Actions::GuestsController" => %w[show remove set_primary],
      "HotelPortal::Bookings::Actions::BillingPartiesController" => %w[show],
      "HotelPortal::Bookings::Actions::InternalNotesController" => %w[show delete],
      "HotelPortal::Folios::Actions::TransactionsController" => %w[show],
      "HotelPortal::Folios::Actions::WindowsController" => %w[show],
      "HotelPortal::Folios::Actions::BillingRoutesController" => %w[show],
      "HotelPortal::Folios::Actions::GroupBillingRoutesController" => %w[show],
      "HotelPortal::StayView::RoomOperationsController" => %w[update],
      "HotelPortal::StayView::RoomBlocksController" => %w[create update destroy finish],
      "HotelPortal::StayView::HousekeepingAssignmentsController" => %w[update],
      "HotelPortal::StayView::HousekeepingStatusesController" => %w[update],
      "HotelPortal::HousekeepingTasksController" => %w[update_room_status update_room_assignment update_remarks],
      "HotelPortal::RequestsController" => %w[move update_status cancel_request archive_request unarchive_request],
      "HotelPortal::CheckoutRequestsController" => %w[complete],
      "HotelPortal::RoomLocksController" => %w[create release],
      "HotelPortal::GuestsController" => %w[create update destroy bulk_destroy toggle_vip toggle_blacklist]
    }.freeze

    TRAINING_ALWAYS_WRITABLE_CONTROLLERS = %w[
      HotelPortal::UserProfilesController
      HotelPortal::OnboardingSubmissionsController
      HotelPortal::OnboardingSessionsController
      HotelPortal::TrainingDecisionsController
    ].freeze

    helper_method :locked_hotel_portal_shell?, :training_mode?, :awaiting_training_decision?, :training_reset_in_progress?
    helper_method :rate_override_allowed?

    private

    # Pricing a stay by hand is its own privilege, separate from taking the
    # booking. Both the creation sheet and the on-demand room row render the
    # field, so the check lives where every portal controller can reach it.
    def rate_override_allowed?
      current_user.has_permission?("override_booking_rate", hotel: current_hotel)
    end

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
      current_hotel.present? && current_hotel.status == "setup"
    end

    # A property that is not live has nothing to run — no rates, no inventory, often no
    # rooms — so the portal around it is a maze of empty pages. Onboarding is the only
    # page that means anything until launch, so that is where everyone goes.
    #
    # In setup that is wherever the owner left off; awaiting review it is the review
    # section, which already states that WAStays is looking at the property. Whoever
    # cannot drive setup gets the explainer instead.
    #
    # Off unless the hotel opts in, so this rolls out one property at a time.
    def enforce_onboarding_lock!
      return if current_hotel.nil? || current_hotel.status.in?(%w[pending_review ready_to_launch live suspended])
      return unless current_hotel.setup_lock_enabled?
      return if current_user&.superadmin?
      return if ONBOARDING_LOCK_EXEMPT.include?(self.class.name)

      redirect_to non_live_hotel_destination
    end

    def non_live_hotel_destination
      return hotel_setup_lock_path(current_hotel) unless HotelPolicy.new(current_user, current_hotel).update?

      hotel_onboarding_section_path(current_hotel, section_key: onboarding_lock_section)
    end

    def onboarding_lock_section
      Onboarding::ResumePageResolver.new(hotel: current_hotel).call.key
    end

    def protect_training_writes!
      return if request.get? || request.head?
      return unless current_hotel&.status.in?(%w[pending_review ready_to_launch])
      return if training_write_allowed?

      redirect_to hotel_dashboard_path(current_hotel),
                  alert: training_write_blocked_message, status: :see_other
    end

    def training_write_allowed?
      return false if training_reset_in_progress?
      return true if TRAINING_ALWAYS_WRITABLE_CONTROLLERS.include?(self.class.name)
      return false unless training_mode?
      return safe_training_folio_transaction? if self.class.name == "HotelPortal::Folios::Actions::TransactionsController"

      TRAINING_WRITE_ACTIONS.fetch(self.class.name, []).include?(action_name)
    end

    def safe_training_folio_transaction?
      transaction = params.fetch(:folio_transaction, ActionController::Parameters.new)
      !(transaction[:transaction_type].to_s == "payment" && transaction[:category].to_s == "refund")
    end

    def training_write_blocked_message
      if training_reset_in_progress?
        "The PMS is read-only while its activity is being cleared."
      elsif awaiting_training_decision?
        "Choose whether to continue with or clear your current PMS activity before making more changes."
      else
        "This setting is read-only while WAStays reviews your property."
      end
    end

    def training_mode?
      current_hotel&.status == "pending_review"
    end

    def awaiting_training_decision?
      current_hotel&.status == "ready_to_launch"
    end

    def training_reset_in_progress?
      current_hotel&.training_reset_state.in?(%w[queued processing])
    end
  end
end
