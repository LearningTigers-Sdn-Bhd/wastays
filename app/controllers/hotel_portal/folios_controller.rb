# frozen_string_literal: true

# Folio index and document exports. Every folio *action* now lives under
# HotelPortal::Folios::Actions; #show is a permanent redirect into the booking
# workspace, which owns the folio UI.

module HotelPortal
  class FoliosController < FinancialsBaseController
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
      authorize_invoice_revision! if params[:revision_number].present?
      @folio = current_hotel.booking_folios
        .includes({ invoice: :revisions }, :ar_invoice, :booking_room, { booking: { booking_rooms: :room_type } }, folio_transactions: [ :transaction_code, :user ])
        .find(params[:folio_id])
      @booking = @folio.booking
      report = ::Reports::Bookings::GenerateInvoice.new(
        folio: @folio,
        printed_by: current_user&.name,
        revision_number: params[:revision_number]
      )

      send_data report.generate,
        filename: "folio-invoice-#{invoice_filename_reference}.pdf",
        type: "application/pdf",
        disposition: request.format.pdf? ? "inline" : "attachment"
    rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError => e
      redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "folio_operations", folio_id: @folio.id), alert: e.message
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def ledger
      @folio = current_hotel.booking_folios
        .includes({ booking: { booking_rooms: :room_type } }, folio_transactions: [ :transaction_code, :user, :night_audit ])
        .find(params[:folio_id])
      @booking = @folio.booking

      ledger_report = ::Reports::Bookings::GenerateFolioLedger.new(folio: @folio, printed_by: current_user&.name)
      filename = "folio-ledger-#{@folio.folio_reference_display.presence || @booking.confirmation_token}"

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
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def invoice_filename_reference
      revision = @folio.invoice&.current_revision
      revision = @folio.invoice&.revisions&.find_by(revision_number: params[:revision_number]) if params[:revision_number].present?
      revision&.document_reference.presence || @booking.confirmation_token
    end

    def authorize_view_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end

    def authorize_invoice_revision!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_audit_logs", hotel: current_hotel)
    end
  end
end
