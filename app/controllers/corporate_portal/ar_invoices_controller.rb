# frozen_string_literal: true

module CorporatePortal
  class ArInvoicesController < CorporatePortal::BaseController
    def index
      refresh_overdue_statuses!
      @presenter = CorporatePortal::AccountsReceivable::IndexPresenter.new(account: current_user.account, params: params, request: request)
    end

    def show
      @ar_invoice = corporate_ar_invoices
        .includes(
          :hotel,
          { booking_folio: :booking },
          { ar_payment_allocations: [ :ar_payment, :reversal ] },
          hotel_corporate_account: :corporate_account
        )
        .find(params[:id])
      @presenter = CorporatePortal::AccountsReceivable::ShowPresenter.new(invoice: @ar_invoice)
      append_breadcrumb @ar_invoice.formatted_invoice_number, corporate_ar_invoice_path(@ar_invoice)
    end

    private

    def refresh_overdue_statuses!
      current_user.account.hotel_corporate_accounts.active.includes(:hotel).map(&:hotel).uniq.each do |hotel|
        ArInvoices::RefreshOverdueStatuses.call(hotel: hotel)
      end
    end
  end
end
