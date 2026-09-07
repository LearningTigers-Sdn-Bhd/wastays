# frozen_string_literal: true

module CorporatePortal
  class ArPaymentsController < CorporatePortal::BaseController
    def index
      refresh_overdue_statuses!
      @presenter = CorporatePortal::AccountsReceivable::PaymentHistoryPresenter.new(account: current_user.account, params: params, request: request)
    end

    def show
      if params[:legacy] == "true"
        @payment = ArPayment.joins(:hotel_corporate_account)
          .where(hotel_corporate_accounts: { corporate_account_id: current_user.account.id })
          .includes(:hotel, ar_payment_allocations: [ { ar_invoice: [ :hotel, :invoice ] }, { reversal: :reversed_by } ])
          .find(params[:id])
        append_breadcrumb @payment.reference_number, corporate_ar_payment_path(@payment, legacy: true)
      else
        @intent = corporate_ar_payment_intents
          .includes(:hotel, :ar_payment, hotel_corporate_account: :corporate_account)
          .find(params[:id])
        @payment = @intent.ar_payment
        append_breadcrumb @intent.external_reference.presence || "Payment attempt ##{@intent.id}", corporate_ar_payment_path(@intent)
      end
    end

    def pay_invoices
      @presenter = CorporatePortal::AccountsReceivable::PayInvoicesPresenter.new(account: current_user.account, params: params)
    end

    def pay_balance
      @presenter = CorporatePortal::AccountsReceivable::PayBalancePresenter.new(account: current_user.account, params: params)
    end

    def choose_method
      @presenter = CorporatePortal::AccountsReceivable::ChooseMethodPresenter.new(
        account: current_user.account,
        hotel_corporate_account_id: params[:hotel_corporate_account_id],
        invoice_ids: params[:invoice_ids]
      )

      redirect_to pay_invoices_corporate_ar_payments_path, alert: "Select at least one invoice to continue." if @presenter.invoices.empty?
    end

    def review
      result = CorporateArPayments::CreateIntent.call(
        user: current_user,
        hotel_corporate_account_id: payment_params[:hotel_corporate_account_id],
        invoice_ids: payment_params[:invoice_ids],
        amount: payment_params[:amount],
        currency: payment_params[:currency],
        gateway: payment_params[:gateway],
        lump_sum: lump_sum?
      )

      if result.success?
        @presenter = CorporatePortal::AccountsReceivable::ReviewPaymentPresenter.new(intent: result.intent)
      elsif lump_sum?
        @presenter = CorporatePortal::AccountsReceivable::PayBalancePresenter.new(account: current_user.account, params: params)
        flash.now[:alert] = result.error
        render :pay_balance, status: :unprocessable_content
      else
        @presenter = CorporatePortal::AccountsReceivable::PayInvoicesPresenter.new(account: current_user.account, params: params)
        flash.now[:alert] = result.error
        render :pay_invoices, status: :unprocessable_content
      end
    end

    def checkout_session
      intent = corporate_ar_payment_intents.find(params[:intent_id])
      result = CorporateArPayments::InitializeCheckout.call(
        intent: intent,
        callback_url: verify_corporate_ar_payments_url(intent_id: intent.id, gateway: intent.gateway)
      )

      if result.success?
        render json: result.payload
      else
        render json: { error: result.error }, status: :unprocessable_content
      end
    end

    def verify
      intent = corporate_ar_payment_intents.find(params[:intent_id])
      result = CorporateArPayments::ProcessVerification.call(
        intent: intent,
        payment_response: payment_response_params
      )

      if result.success?
        redirect_to corporate_ar_payment_path(intent), notice: "Payment received. Hotel finance will allocate it to invoices."
      else
        redirect_to corporate_ar_payment_path(intent), alert: result.error
      end
    end

    private

    def refresh_overdue_statuses!
      current_user.account.hotel_corporate_accounts.active.includes(:hotel).map(&:hotel).uniq.each do |hotel|
        ArInvoices::RefreshOverdueStatuses.call(hotel: hotel)
      end
    end

    def corporate_ar_payment_intents
      CorporateArPaymentIntent.where(corporate_account: current_user.account)
    end

    def payment_params
      params.fetch(:corporate_ar_payment, {}).permit(:hotel_corporate_account_id, :amount, :currency, :gateway, :lump_sum, invoice_ids: [])
    end

    def lump_sum?
      ActiveModel::Type::Boolean.new.cast(payment_params[:lump_sum])
    end

    def payment_response_params
      from_nested = params.fetch(:payment_response, {}).permit(:razorpay_payment_id, :razorpay_order_id, :razorpay_signature).to_h
      from_redirect = params.permit(:razorpay_payment_id, :razorpay_order_id, :razorpay_signature).to_h

      from_nested.merge(from_redirect).symbolize_keys
    end
  end
end
