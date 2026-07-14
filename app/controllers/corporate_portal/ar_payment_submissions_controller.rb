# frozen_string_literal: true

module CorporatePortal
  class ArPaymentSubmissionsController < CorporatePortal::BaseController
    def show
      @submission = corporate_ar_payment_submissions
        .includes(:hotel, :ar_payment, ar_payment_submission_allocations: :ar_invoice, hotel_corporate_account: :corporate_account)
        .find(params[:id])
    end

    def new
      @invoices = corporate_open_invoices.where(id: requested_invoice_ids)
      @ar_payment_submission = ArPaymentSubmission.new(
        currency: @invoices.first&.currency || corporate_hotel_corporate_accounts.first&.credit_currency,
        payment_method: "bank_transfer",
        received_at: Date.current
      )
    end

    def create
      invoices = corporate_open_invoices.where(id: requested_invoice_ids)

      if invoices.empty?
        return redirect_to pay_invoices_corporate_ar_payments_path, alert: "Select at least one outstanding invoice to submit this payment for."
      end

      hotel_corporate_account = invoices.first.hotel_corporate_account
      unless invoices.all? { |invoice| invoice.hotel_corporate_account_id == hotel_corporate_account.id }
        return redirect_to pay_invoices_corporate_ar_payments_path, alert: "Selected invoices must belong to the same corporate account."
      end

      @ar_payment_submission = hotel_corporate_account.ar_payment_submissions.build(
        submission_params.except(:ar_invoice_ids).merge(
          hotel: hotel_corporate_account.hotel,
          submitted_by: current_user,
          amount: invoices.sum(&:outstanding_amount),
          currency: invoices.first.currency
        )
      )
      invoices.each do |invoice|
        @ar_payment_submission.ar_payment_submission_allocations.build(ar_invoice: invoice, amount: invoice.outstanding_amount)
      end

      if @ar_payment_submission.save
        redirect_to corporate_ar_payments_path, notice: "Payment submitted for hotel review."
      else
        @invoices = invoices
        flash.now[:alert] = @ar_payment_submission.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end

    private

    def corporate_ar_payment_submissions
      ArPaymentSubmission.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id })
    end

    def corporate_hotel_corporate_accounts
      @corporate_hotel_corporate_accounts ||= current_user.account.hotel_corporate_accounts.active.includes(:hotel)
    end
    helper_method :corporate_hotel_corporate_accounts

    def corporate_open_invoices
      @corporate_open_invoices ||= ArInvoice.joins(:hotel_corporate_account)
        .where(hotel_corporate_accounts: { corporate_account_id: current_user.account_id, status: "active" })
        .with_open_balance
        .includes(:hotel, hotel_corporate_account: :corporate_account)
        .order(:due_on)
    end
    helper_method :corporate_open_invoices

    def requested_invoice_ids
      Array(params[:ar_invoice_ids].presence || submission_params[:ar_invoice_ids].presence || params[:ar_invoice_id]).reject(&:blank?)
    end

    def submission_params
      params.fetch(:ar_payment_submission, {}).permit(:reference_number, :currency, :received_at, :payment_method, :notes, :slip, ar_invoice_ids: [])
    end
  end
end
