# frozen_string_literal: true

module CorporatePortal
  class ArPaymentSubmissionsController < CorporatePortal::BaseController
    def index
      @submissions = corporate_ar_payment_submissions
        .includes(:hotel, :ar_payment, :ar_invoice, hotel_corporate_account: :corporate_account)
        .order(created_at: :desc)
    end

    def show
      @submission = corporate_ar_payment_submissions
        .includes(:hotel, :ar_payment, :ar_invoice, hotel_corporate_account: :corporate_account)
        .find(params[:id])
    end

    def new
      preselected = corporate_open_invoices.find_by(id: params[:ar_invoice_id])
      @ar_payment_submission = ArPaymentSubmission.new(
        ar_invoice_id: preselected&.id,
        amount: preselected&.outstanding_amount,
        currency: preselected&.currency || corporate_hotel_corporate_accounts.first&.credit_currency,
        payment_method: "bank_transfer",
        received_at: Date.current
      )
    end

    def create
      invoice = corporate_open_invoices.find_by(id: submission_params[:ar_invoice_id])

      unless invoice
        return redirect_to new_corporate_ar_payment_submission_path, alert: "Select an outstanding invoice to submit this payment for."
      end

      @ar_payment_submission = invoice.hotel_corporate_account.ar_payment_submissions.build(
        submission_params.except(:ar_invoice_id).merge(ar_invoice: invoice, hotel: invoice.hotel, submitted_by: current_user)
      )

      if @ar_payment_submission.save
        redirect_to corporate_ar_payment_submissions_path, notice: "Payment submitted for hotel review."
      else
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

    def submission_params
      params.require(:ar_payment_submission).permit(:ar_invoice_id, :amount, :currency, :reference_number, :received_at, :payment_method, :notes, :slip)
    end
  end
end
