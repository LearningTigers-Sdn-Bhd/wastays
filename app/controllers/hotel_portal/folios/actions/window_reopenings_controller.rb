# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "reopen folio window".
      class WindowReopeningsController < BaseController
        def show
          return create if request.post?

          @folio = @booking.booking_folios.find(params[:folio_id])
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_windows")
        end

        def create
          folio = @booking.booking_folios.find(params[:folio_id])
          result = ::Folios::Lifecycle::ReopenFolio.call(folio: folio, user: current_user, reason: folio_params[:reason])

          return complete_action(alert: result.error) unless result.success?

          if params[:return_to].blank?
            @return_to = hotel_booking_workspace_path(current_hotel, @booking, tab: "folio_operations", folio_id: folio.id)
          end
          complete_action(notice: "Folio window reopened.")
        end

        def folio_params
          params.fetch(:booking_folio, {}).permit(:reason)
        end
      end
    end
  end
end
