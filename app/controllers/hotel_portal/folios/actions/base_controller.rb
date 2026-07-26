# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Base controller for the Sheet-based folio-action workflows.
      #
      # Owns the `folio_action_sheet` frame and the `complete_folio_action`
      # contract. Does not depend on the legacy Offcanvas implementation.
      class BaseController < HotelPortal::BaseController
        include FolioActionCompletion

        before_action :authorize_view_bookings!
        before_action :authorize_folio_action!
        before_action :set_booking
        before_action :set_return_to

        private

        def authorize_view_bookings!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
        end

        # Folio permissions are per-verb — posting even derives its slug from
        # transaction_type + category — so there is no sane default here. Every
        # subclass declares its own gate; a default would silently under-gate.
        def authorize_folio_action!
          raise NotImplementedError, "#{self.class} must define authorize_folio_action!"
        end

        def permit_folio!(slug)
          allowed = (current_user.respond_to?(:superadmin?) && current_user.superadmin?) ||
            current_user.has_permission?(slug, hotel: current_hotel)
          raise Pundit::NotAuthorizedError unless allowed
        end

        def set_booking
          @booking = current_hotel.bookings.find(params[:booking_id])
        end

        # hotel_folio_path is a 301 to the workspace, so target the destination
        # directly rather than paying the redirect on every completion.
        def set_return_to
          @return_to = folio_action_return_to(
            fallback: hotel_booking_workspace_path(current_hotel, @booking, tab: "folio_operations")
          )
        end

        # The Turbo Frame that launched this action. A stacked launcher targets
        # `folio_action_sheet_secondary`, so completion must close that frame's
        # dialog rather than always the primary one.
        def requesting_sheet_frame
          turbo_frame_request_id.presence || "folio_action_sheet"
        end

        def complete_action(notice: nil, alert: nil)
          return complete_folio_action(destination: @return_to, notice: notice, frame: requesting_sheet_frame) if alert.blank?

          respond_to do |format|
            format.turbo_stream do
              flash[:alert] = alert
              render_folio_action_completion(@return_to, frame: requesting_sheet_frame)
            end
            format.html { redirect_to @return_to, alert: alert, status: :see_other }
          end
        end
      end
    end
  end
end
