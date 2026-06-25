# frozen_string_literal: true

module HotelPortal
  class ArInvoicesController < BaseController
    before_action :authorize_view_reports!

    def index
      ArInvoices::RefreshOverdueStatuses.call(hotel: current_hotel)
      @presenter = HotelPortal::AccountsReceivable::IndexPresenter.new(hotel: current_hotel, params: params)
    end

    def aging
      ArInvoices::RefreshOverdueStatuses.call(hotel: current_hotel)
      report = ArInvoices::AgingReport.call(hotel: current_hotel)
      @presenter = HotelPortal::AccountsReceivable::AgingPresenter.new(report: report)
    end

    def show
      @ar_invoice = current_hotel.ar_invoices
        .includes(
          { booking_folio: :booking },
          { ar_payment_allocations: [ :ar_payment, :reversal ] },
          hotel_corporate_account: :corporate_account
        )
        .find(params[:id])
      @presenter = HotelPortal::AccountsReceivable::ShowPresenter.new(invoice: @ar_invoice, hotel: current_hotel)
    end

    private

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
