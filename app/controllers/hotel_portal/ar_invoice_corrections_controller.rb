# frozen_string_literal: true

module HotelPortal
  class ArInvoiceCorrectionsController < FinancialsBaseController
    def update
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_folio_windows", hotel: current_hotel)
      correction = current_hotel_corrections.find(params[:id])
      result = if params[:send_documents] == "1"
        ArInvoices::SendCorrection.call(correction: correction)
      else
        ArInvoices::RetryCorrection.call(correction: correction)
      end
      redirect_to hotel_ar_invoice_path(current_hotel, correction.replacement_receivable || correction.original_receivable),
        **(result.success? ? { notice: "Correction documents queued." } : { alert: result.error })
    end

    def credit
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
      correction = current_hotel_corrections.find(params[:id])
      raise ActiveRecord::RecordNotFound if correction.credit_reference.blank?
      send_data ::Reports::AccountsReceivable::GenerateCorrectionCredit.new(correction: correction).generate,
        filename: "#{correction.credit_reference}.pdf", type: "application/pdf", disposition: "inline"
    end

    private

    def current_hotel_corrections
      ArInvoiceCorrection.where(hotel: current_hotel)
    end
  end
end
