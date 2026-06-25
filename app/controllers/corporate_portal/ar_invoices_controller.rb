# frozen_string_literal: true

module CorporatePortal
  class ArInvoicesController < CorporatePortal::BaseController
    def index
      @ar_invoices = corporate_ar_invoices
        .includes(:hotel, :booking_folio, hotel_corporate_account: :corporate_account)
        .order(due_on: :asc, issued_on: :desc, invoice_number: :desc)
      @outstanding_by_currency = corporate_ar_invoices.with_open_balance.group(:currency).sum(:outstanding_amount)
    end

    def show
      @ar_invoice = corporate_ar_invoices
        .includes(:hotel, :booking_folio, ar_payment_allocations: [ :ar_payment, :reversal ], hotel_corporate_account: :corporate_account)
        .find(params[:id])
      append_breadcrumb "AR-#{@ar_invoice.invoice_number}", corporate_ar_invoice_path(@ar_invoice)
    end
  end
end
