# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      # Read-only booking Audit Trail rendered into the booking_action_sheet.
      #
      # Gated on view_bookings + the full_audit_trail feature (like the legacy
      # BookingControlPanelsController#audit_trail), not the base manage_bookings
      # authorization.
      class AuditTrailsController < BaseController
        include BookingAuditable

        skip_before_action :authorize_manage_bookings!
        before_action :authorize_view_bookings!
        before_action :require_audit_feature!

        def show
          @presenter = BookingControlPanelPresenter.new(@booking, params: params, hotel: current_hotel)
          set_audit_logs(@booking, group_booking: (@booking.group_booking if @presenter.group_overview?))
          render :show, layout: false
        end

        private

        def authorize_view_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
        end

        def require_audit_feature!
          require_feature!("full_audit_trail")
        end
      end
    end
  end
end
