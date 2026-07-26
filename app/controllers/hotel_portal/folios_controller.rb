# frozen_string_literal: true

# Folio index and document exports. Every folio *action* now lives under
# HotelPortal::Folios::Actions; #show is a permanent redirect into the booking
# workspace, which owns the folio UI.

module HotelPortal
  class FoliosController < BaseController
    before_action :authorize_view_bookings!

    def index
      @folio_index = HotelPortal::Folios::IndexPresenter.new(
        hotel: current_hotel,
        params: params
      )
      render "hotel_portal/folios/index/index"
    end

    def needs_attention
      append_breadcrumb "Needs Attention"
      @folio_index = HotelPortal::Folios::IndexPresenter.new(
        hotel: current_hotel,
        params: params,
        attention_only: true
      )
      render "hotel_portal/folios/index/needs_attention"
    end

    def show
      booking = current_hotel.bookings.find(params[:booking_id])
      query = { tab: "folio_operations" }
      query[:folio_id] = params[:active_folio_id] if params[:active_folio_id].present?
      redirect_to hotel_booking_workspace_path(current_hotel, booking, query), status: :moved_permanently
    end

    def invoice
      @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions, booking_rooms: :room_type).find(params[:booking_id])
      unless @booking.booking_folio&.status == "closed"
        return redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "folio_operations"), alert: "Folio invoice is only available for checked-out bookings with a closed folio."
      end

      send_data ::Reports::Bookings::GenerateInvoice.new(booking: @booking, printed_by: current_user&.name).generate,
        filename: "folio-invoice-#{@booking.formatted_invoice_number || @booking.confirmation_token}.pdf",
        type: "application/pdf",
        disposition: request.format.pdf? ? "inline" : "attachment"
    end

    def ledger
      @booking = current_hotel.bookings.includes(:booking_rooms, booking_folios: [ { folio_transactions: :transaction_code }, { hotel_corporate_account: :corporate_account } ]).find(params[:booking_id])
      return redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "folio_operations"), alert: "Booking has no folio." unless @booking.booking_folio

      ledger_report = ::Reports::Bookings::GenerateFolioLedger.new(booking: @booking, printed_by: current_user&.name)
      filename = "folio-ledger-#{@booking.folio_account_reference_display.presence || @booking.confirmation_token}"

      respond_to do |format|
        format.csv do
          send_data ledger_report.generate_csv,
            filename: "#{filename}.csv",
            type: "text/csv",
            disposition: "attachment"
        end

        format.pdf do
          send_data ledger_report.generate_pdf,
            filename: "#{filename}.pdf",
            type: "application/pdf",
            disposition: "inline"
        end
      end
    end

    private

    def authorize_view_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end
  end
end
