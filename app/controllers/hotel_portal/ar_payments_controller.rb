# frozen_string_literal: true

module HotelPortal
  class ArPaymentsController < BaseController
    before_action :authorize_view_reports!

    def index
      @ar_payments = current_hotel.ar_payments
        .includes(:ar_payment_allocations, hotel_corporate_account: :corporate_account)
        .order(received_at: :desc, created_at: :desc)
    end

    def new
      set_context
    end

    def create
      @hotel_corporate_account = current_hotel.hotel_corporate_accounts.find(ar_payment_params[:hotel_corporate_account_id])
      result = ArPayments::RecordPayment.call(
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
        redirect_to redirect_after_create, notice: "Corporate payment recorded."
      else
        set_context
        @ar_payment_error = result.error
        flash.now[:alert] = result.error
        render :new, status: :unprocessable_content
      end
    end

    private

    def set_context
      @source_invoice = current_hotel.ar_invoices.includes(hotel_corporate_account: :corporate_account).find_by(id: params[:ar_invoice_id].presence || ar_payment_params[:ar_invoice_id].presence)
      @hotel_corporate_account = @source_invoice&.hotel_corporate_account || current_hotel.hotel_corporate_accounts.includes(:corporate_account).find_by(id: ar_payment_params[:hotel_corporate_account_id].presence || params[:hotel_corporate_account_id].presence)
      @hotel_corporate_account ||= current_hotel.hotel_corporate_accounts.active.includes(:corporate_account).order(created_at: :desc).first
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

    def redirect_after_create
      if ar_payment_params[:ar_invoice_id].present?
        hotel_ar_invoice_path(current_hotel, ar_payment_params[:ar_invoice_id])
      else
        hotel_ar_invoices_path(current_hotel)
      end
    end

    def ar_payment_params
      params.fetch(:ar_payment, {}).permit(:hotel_corporate_account_id, :ar_invoice_id, :amount, :currency, :reference_number, :received_at, :payment_method, :notes)
    end

    def allocation_params
      params.fetch(:allocations, {}).permit!.to_h
    end

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
