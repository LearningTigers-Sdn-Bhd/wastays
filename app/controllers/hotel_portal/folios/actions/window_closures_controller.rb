# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "close folio window". A folio backed by an active
      # direct-bill corporate account closes as Direct Bill and raises an AR
      # invoice; everything else must already be settled.
      class WindowClosuresController < BaseController
        def show
          return create if request.post?

          load_folio
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_folio_windows")
        end

        def load_folio
          @folio = @booking.booking_folios.find(params[:folio_id])
          @direct_bill_available = direct_bill_available?(@folio)
        end

        def create
          folio = @booking.booking_folios.find(params[:folio_id])
          result = ::Folios::Lifecycle::CloseFolio.call(
            folio: folio,
            user: current_user,
            reason: folio_params[:reason],
            settlement_method: folio_params[:settlement_method]
          )

          return complete_action(alert: result.error) unless result.success?

          if params[:return_to].blank?
            @return_to = hotel_booking_workspace_path(current_hotel, @booking, tab: "folio_operations", folio_id: folio.id)
          end
          complete_action(notice: "Folio window closed.")
        end

        def direct_bill_available?(folio)
          folio.payer_type == "company" &&
            folio.hotel_corporate_account&.active? &&
            folio.hotel_corporate_account&.direct_bill_enabled? &&
            folio.outstanding_balance.to_d.positive?
        end

        def folio_params
          params.fetch(:booking_folio, {}).permit(:reason, :settlement_method)
        end
      end
    end
  end
end
