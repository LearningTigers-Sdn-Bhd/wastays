# frozen_string_literal: true

module HotelPortal
  module Folios
    module Actions
      # Sheet-based "issue adjustment note". When a folio moves after its
      # original e-invoice was validated, LHDN wants a debit note (03) for an
      # increase or a credit note (02) for a refund, referencing the original
      # UUID - never a reissued invoice.
      class EInvoiceAdjustmentsController < BaseController
        def show
          return create if request.post?

          @preview = EInvoice::IssueAdjustment.preview(@booking)
          render :show, layout: false
        end

        private

        def authorize_folio_action!
          permit_folio!("manage_bookings")
        end

        def create
          result = EInvoice::IssueAdjustment.call(@booking)

          if result[:success]
            @return_to = hotel_e_invoice_submission_path(current_hotel, result[:submission]) if params[:return_to].blank?
            complete_action(notice: "Adjustment note is being prepared and sent to LHDN.")
          elsif result[:skipped]
            complete_action(alert: result[:message])
          else
            complete_action(alert: result[:error] || "Unable to issue adjustment note right now.")
          end
        end
      end
    end
  end
end
