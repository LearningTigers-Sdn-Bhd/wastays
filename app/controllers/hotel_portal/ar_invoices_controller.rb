# frozen_string_literal: true

module HotelPortal
  class ArInvoicesController < BaseController
    before_action :authorize_view_reports!

    def index
      @ar_invoices = current_hotel.ar_invoices
        .includes(:booking_folio, hotel_corporate_account: :corporate_account)
        .order(due_on: :asc, issued_on: :desc, invoice_number: :desc)
    end

    def show
      @ar_invoice = current_hotel.ar_invoices
        .includes(:booking_folio, ar_payment_allocations: :ar_payment, hotel_corporate_account: :corporate_account)
        .find(params[:id])
    end

    private

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
