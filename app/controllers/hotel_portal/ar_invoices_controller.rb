# frozen_string_literal: true

module HotelPortal
  class ArInvoicesController < FinancialsBaseController
    before_action :authorize_view_reports!

    def index
      ArInvoices::RefreshOverdueStatuses.call(hotel: current_hotel)
      @presenter = HotelPortal::AccountsReceivable::IndexPresenter.new(hotel: current_hotel, params: params)
    end

    def aging
      ArInvoices::RefreshOverdueStatuses.call(hotel: current_hotel)
      report = ArInvoices::AgingReport.call(hotel: current_hotel)
      @presenter = HotelPortal::AccountsReceivable::AgingPresenter.new(report: report, query: params[:query], account_type: params[:account_type])
    end

    def agent_summary
      redirect_to hotel_ar_aging_path(current_hotel)
    end

    def aging_summary_pdf
      ArInvoices::RefreshOverdueStatuses.call(hotel: current_hotel)
      report = ArInvoices::AgingReport.call(
        hotel: current_hotel,
        account_types: params[:account_type].presence_in(HotelCorporateAccount::ACCOUNT_TYPES),
        query: params[:query]
      )
      document = ::Reports::AccountsReceivable::GenerateAgingSummary.new(
        hotel: current_hotel,
        report: report,
        printed_by: current_user&.name
      ).generate
      send_data document,
        filename: "aging-summary-statement-#{current_hotel.slug}-#{report.as_of_date}.pdf",
        type: "application/pdf",
        disposition: "inline"
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

    def pdf
      invoice = current_hotel.ar_invoices
        .includes(
          { invoice: :revisions },
          { booking_folio: [ :folio_transactions, :booking_room, { booking: { booking_rooms: :room_type } }, { booking_billing_party: :billing_terms } ] },
          hotel_corporate_account: :corporate_account
        )
        .find(params[:id])
      document = ::Reports::AccountsReceivable::GenerateInvoice.new(invoice:, printed_by: current_user&.name).generate

      send_data document,
        filename: "ar-invoice-#{invoice.formatted_invoice_number}.pdf",
        type: "application/pdf",
        disposition: "inline"
    end

    private

    def authorize_view_reports!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
    end
  end
end
