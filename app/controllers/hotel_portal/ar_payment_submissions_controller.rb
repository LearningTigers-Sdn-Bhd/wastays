# frozen_string_literal: true

module HotelPortal
  class ArPaymentSubmissionsController < FinancialsBaseController
    before_action :authorize_manage_ar_payments!
    before_action :set_submission, only: %i[show reject]
    before_action :append_page_breadcrumb, only: :show

    def show; end

    def reject
      if @submission.reject!(reason: reject_params[:rejection_reason], reviewed_by: current_user)
        redirect_to hotel_ar_payments_path(current_hotel), notice: "Payment submission rejected."
      else
        redirect_to hotel_ar_payment_submission_path(current_hotel, @submission), alert: @submission.errors.full_messages.to_sentence
      end
    end

    private

    # Without this the submission shares the "Payment Record" crumb with the
    # index it was opened from, and the tab cannot tell the two apart.
    def append_page_breadcrumb
      append_breadcrumb @submission.hotel_corporate_account.corporate_account.name
    end

    def set_submission
      @submission = current_hotel.ar_payment_submissions
        .includes(:ar_payment, ar_payment_submission_allocations: :ar_invoice, hotel_corporate_account: :corporate_account)
        .find(params[:id])
    end

    def reject_params
      params.permit(:rejection_reason)
    end

    def authorize_manage_ar_payments!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_ar_payments", hotel: current_hotel)
    end
  end
end
