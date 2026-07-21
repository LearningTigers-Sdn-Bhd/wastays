# frozen_string_literal: true

module HotelPortal
  class ArPaymentsController < BaseController
    before_action :authorize_view_reports!
    before_action :authorize_manage_ar_payments!, only: %i[new create eligible_invoices]

    def index
      @presenter = HotelPortal::AccountsReceivable::PaymentRecordPresenter.new(hotel: current_hotel, params: params)
    end

    def show
      payment = current_hotel.ar_payments
        .includes(
          { ar_payment_allocations: [ :ar_invoice, { reversal: :reversed_by } ] },
          hotel_corporate_account: :corporate_account
        )
        .find(params[:id])
      @presenter = HotelPortal::ArPayments::ShowPresenter.new(
        payment: payment,
        hotel: current_hotel,
        can_manage: can_manage_ar_payments?
      )
    end

    def new
      @ar_payment_submission = find_pending_submission
      set_context
      apply_submission_context if @ar_payment_submission.present?
    end

    def create
      @hotel_corporate_account = current_hotel.hotel_corporate_accounts.find(ar_payment_params[:hotel_corporate_account_id])
      submission = find_pending_submission

      result = ::ArPayments::RecordPayment.call(
        hotel: current_hotel,
        hotel_corporate_account: @hotel_corporate_account,
        user: current_user,
        amount: ar_payment_params[:amount],
        currency: ar_payment_params[:currency],
        reference_number: ar_payment_params[:reference_number],
        received_at: ar_payment_params[:received_at],
        payment_method: ar_payment_params[:payment_method],
        notes: ar_payment_params[:notes],
        allocations: allocation_params
      )

      if result.success?
        submission&.approve!(ar_payment: result.ar_payment, reviewed_by: current_user)
        redirect_to hotel_ar_payment_path(current_hotel, result.ar_payment), notice: "Corporate payment recorded."
      else
        set_context
        @ar_payment_submission = submission
        apply_submission_context if @ar_payment_submission.present?
        @ar_payment_error = result.error
        flash.now[:alert] = result.error
        render :new, status: :unprocessable_content
      end
    end

    def eligible_invoices
      @hotel_corporate_account = current_hotel.hotel_corporate_accounts.find_by(id: params[:hotel_corporate_account_id])
      @open_invoices = open_invoices
      render partial: "invoice_allocations", locals: { open_invoices: @open_invoices, source_allocations: {}, readonly: false }
    end

    private

    def find_pending_submission
      current_hotel.ar_payment_submissions.pending.includes(ar_payment_submission_allocations: { ar_invoice: [ :hotel, { booking_folio: :booking } ] }).find_by(id: params[:ar_payment_submission_id])
    end

    def apply_submission_context
      @hotel_corporate_account = @ar_payment_submission.hotel_corporate_account
      @source_allocations = @ar_payment_submission.ar_payment_submission_allocations.index_by(&:ar_invoice_id).transform_values(&:amount)
      # Only the invoices the agent picked when submitting — not the account's full open
      # invoice list — since this payment is already fixed to exactly those invoices.
      @open_invoices = @ar_payment_submission.ar_payment_submission_allocations.map(&:ar_invoice).sort_by(&:due_on)
    end

    def set_context
      @source_invoice = current_hotel.ar_invoices.includes(hotel_corporate_account: :corporate_account).find_by(id: params[:ar_invoice_id].presence || ar_payment_params[:ar_invoice_id].presence)
      @hotel_corporate_account = @source_invoice&.hotel_corporate_account || current_hotel.hotel_corporate_accounts.includes(:corporate_account).find_by(id: ar_payment_params[:hotel_corporate_account_id].presence || params[:hotel_corporate_account_id].presence)
      @hotel_corporate_account ||= current_hotel.hotel_corporate_accounts.active.includes(:corporate_account).order(created_at: :desc).first
      @source_allocations = @source_invoice.present? ? { @source_invoice.id => @source_invoice.outstanding_amount } : {}
      @open_invoices = open_invoices
    end

    def open_invoices
      return ArInvoice.none if @hotel_corporate_account.blank?

      current_hotel.ar_invoices
        .with_open_balance
        .where(hotel_corporate_account: @hotel_corporate_account)
        .includes(:booking_folio)
        .order(due_on: :asc, invoice_number: :asc)
    end

    def ar_payment_params
      params.fetch(:ar_payment, {}).permit(:hotel_corporate_account_id, :ar_invoice_id, :amount, :currency, :reference_number, :received_at, :payment_method, :notes)
    end

    def allocation_params
      params.fetch(:allocations, {})
    end

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end

    def authorize_manage_ar_payments!
      raise Pundit::NotAuthorizedError unless can_manage_ar_payments?
    end

    def can_manage_ar_payments?
      current_user.has_permission?("manage_ar_payments", hotel: current_hotel)
    end
  end
end
