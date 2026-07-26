# frozen_string_literal: true

# LEGACY: frozen pending booking-workspace migration. Do not add features here.

module HotelPortal
  class FoliosController < BaseController
    include OffcanvasTransactionCompletion

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

    def new_window
      authorize_manage_folio_windows!
      @booking = current_hotel.bookings.find(params[:booking_id])
      set_company_government_accounts
      @folio = @booking.booking_folios.build(
        name: "External Folio",
        folio_type: "external",
        payer_type: "company",
        currency: @booking.currency.presence || current_hotel.default_currency
      )
      @sheet_title = "Add Folio Window"
      @sheet_description = "Create a separate billing window for this booking."
      @form_url = windows_hotel_folio_path(current_hotel, @booking)
      @form_method = :post
      @submit_label = "Create Folio"
      @folio_origin = params[:origin].presence
      render "hotel_portal/folios/manage_windows/offcanvas"
    end

    def edit_window
      authorize_manage_folio_windows!
      @booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      @folio = @booking.booking_folios.find(params[:folio_id])
      set_company_government_accounts
      @sheet_title = "Edit Folio Window"
      @sheet_description = "Update folio details or make this the primary folio for the booking."
      @form_url = window_hotel_folio_path(current_hotel, @booking, @folio)
      @form_method = :patch
      @submit_label = "Save Changes"
      @folio_origin = params[:origin].presence
      render "hotel_portal/folios/manage_windows/offcanvas"
    end

    def create_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.find(params[:booking_id])
      result = ::Folios::Lifecycle::CreateFolio.call(booking: booking, user: current_user, attributes: folio_window_params)

      if result.success?
        respond_with_offcanvas_completion(
          hotel_booking_workspace_path(current_hotel, booking, tab: "folio_operations", folio_id: result.folio.id),
          notice: "Folio window created."
        )
      else
        respond_with_offcanvas_completion(
          hotel_booking_workspace_path(current_hotel, booking, tab: "folio_operations"),
          alert: result.error
        )
      end
    end

    def update_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      folio = booking.booking_folios.find(params[:folio_id])
      result = ::Folios::Lifecycle::UpdateFolio.call(
        folio: folio,
        user: current_user,
        attributes: folio_window_params
      )

      respond_with_offcanvas_completion(
        hotel_booking_workspace_path(current_hotel, booking, tab: "folio_operations", folio_id: folio.id),
        **(result.success? ? { notice: "Folio window updated." } : { alert: result.error })
      )
    end

    def close_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      folio = booking.booking_folios.find(params[:folio_id])
      result = ::Folios::Lifecycle::CloseFolio.call(
        folio: folio,
        user: current_user,
        reason: folio_window_params[:reason],
        settlement_method: folio_window_params[:settlement_method]
      )

      redirect_to hotel_booking_workspace_path(current_hotel, booking, tab: "folio_operations", folio_id: folio.id),
        result.success? ? { notice: "Folio window closed." } : { alert: result.error }
    end

    def reopen_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      folio = booking.booking_folios.find(params[:folio_id])
      result = ::Folios::Lifecycle::ReopenFolio.call(folio: folio, user: current_user, reason: folio_window_params[:reason])

      redirect_to hotel_booking_workspace_path(current_hotel, booking, tab: "folio_operations", folio_id: folio.id),
        result.success? ? { notice: "Folio window reopened." } : { alert: result.error }
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

    def authorize_manage_folio_windows!
      allowed = current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
        current_user.has_permission?("manage_folio_windows", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end

    def folio_window_params
      params.fetch(:booking_folio, {}).permit(:name, :folio_type, :payer_type, :payer_id, :hotel_corporate_account_id, :currency, :reason, :settlement_method, :is_primary, :set_folio_as_primary_reason)
    end

    def set_company_government_accounts
      @company_government_accounts = current_hotel.hotel_corporate_accounts
        .active
        .includes(corporate_account: :users)
        .order(created_at: :desc)
    end

    def folio_origin_params
      params[:origin] == "folios" || params[:folio_origin] == "folios" ? { origin: "folios" } : {}
    end

    def folio_redirect_state(tab:)
      folio_origin_params.merge(tab: tab).compact
    end

    def respond_with_offcanvas_completion(destination, notice: nil, alert: nil)
      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = notice if notice.present?
          flash[:alert] = alert if alert.present?
          render_offcanvas_completion(destination)
        end
        format.html { redirect_to destination, { notice: notice, alert: alert }.compact }
      end
    end
  end
end
