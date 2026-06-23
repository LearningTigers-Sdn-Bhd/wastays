# frozen_string_literal: true

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

    def show
      @booking = current_hotel.bookings
        .includes({ booking_rooms: :room_type }, booking_folios: [ { folio_transactions: [ :user, :transaction_code ] }, :folio_forecasted_charges ])
        .find(params[:booking_id])
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      @folio_show = HotelPortal::Folios::ShowPresenter.new(booking: @booking, hotel: current_hotel, user: current_user, active_folio_id: params[:active_folio_id])
      set_navigation_context
      set_breadcrumbs
      render "hotel_portal/folios/show/index"
    end

    def new_window
      authorize_manage_folio_windows!
      @booking = current_hotel.bookings.find(params[:booking_id])
      @folio = @booking.booking_folios.build(
        name: "Custom Folio",
        folio_type: "custom",
        payer_type: "guest",
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
      result = ::Folios::CreateFolio.call(booking: booking, user: current_user, attributes: folio_window_params)

      if result.success?
        redirect_to hotel_folio_path(current_hotel, booking, active_folio_id: result.folio.id, **folio_origin_params), notice: "Folio window created."
      else
        redirect_to hotel_folio_path(current_hotel, booking, **folio_origin_params), alert: result.error
      end
    end

    def update_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      folio = booking.booking_folios.find(params[:folio_id])
      result = ::Folios::UpdateFolio.call(
        folio: folio,
        user: current_user,
        attributes: folio_window_params
      )

      redirect_to hotel_folio_path(current_hotel, booking, active_folio_id: folio.id, **folio_origin_params),
        result.success? ? { notice: "Folio window updated." } : { alert: result.error }
    end

    def close_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      folio = booking.booking_folios.find(params[:folio_id])
      result = ::Folios::CloseFolio.call(folio: folio, user: current_user, reason: folio_window_params[:reason])

      redirect_to hotel_folio_path(current_hotel, booking, active_folio_id: folio.id, **folio_origin_params),
        result.success? ? { notice: "Folio window closed." } : { alert: result.error }
    end

    def reopen_window
      authorize_manage_folio_windows!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      folio = booking.booking_folios.find(params[:folio_id])
      result = ::Folios::ReopenFolio.call(folio: folio, user: current_user, reason: folio_window_params[:reason])

      redirect_to hotel_folio_path(current_hotel, booking, active_folio_id: folio.id, **folio_origin_params),
        result.success? ? { notice: "Folio window reopened." } : { alert: result.error }
    end

    def move_forecast
      authorize_manage_folio_movements!
      booking = current_hotel.bookings.includes(:booking_folios).find(params[:booking_id])
      forecast = FolioForecastedCharge.joins(:booking_folio).where(booking_folios: { booking_id: booking.id, hotel_id: current_hotel.id }).find(params[:forecast_id])
      target_folio = booking.booking_folios.find(folio_operation_params[:target_folio_id])
      result = ::Folios::MoveForecast.call(
        forecast: forecast,
        target_folio: target_folio,
        user: current_user,
        reason: folio_operation_params[:reason]
      )

      redirect_to hotel_folio_path(current_hotel, booking, active_folio_id: (result.success? ? target_folio.id : forecast.booking_folio_id), **folio_origin_params),
        result.success? ? { notice: "Upcoming charge moved." } : { alert: result.error }
    end

    def invoice
      @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions, booking_rooms: :room_type).find(params[:booking_id])
      unless @booking.booking_folio&.status == "closed"
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Folio invoice is only available for checked-out bookings with a closed folio."
      end

      send_data ::Reports::Bookings::GenerateInvoice.new(booking: @booking, printed_by: current_user&.name).generate,
        filename: "folio-invoice-#{@booking.formatted_invoice_number || @booking.confirmation_token}.pdf",
        type: "application/pdf",
        disposition: request.format.pdf? ? "inline" : "attachment"
    end

    def ledger
      @booking = current_hotel.bookings.includes(:booking_rooms, booking_folios: { folio_transactions: :transaction_code }).find(params[:booking_id])
      return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Booking has no folio." unless @booking.booking_folio

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

    def set_navigation_context
      if params[:origin] == "folios"
        @folio_origin = "folios"
        @folio_back_path = hotel_folios_path(current_hotel)
        @folio_back_label = "Back to All Folios"
      else
        @folio_back_path = hotel_booking_path(current_hotel, @booking)
        @folio_back_label = "Back to Booking"
      end
    end

    def set_breadcrumbs
      if @folio_origin == "folios"
        override_breadcrumbs(
          { label: "Finance" },
          { label: "Folios", path: hotel_folios_path(current_hotel) },
          { label: @booking.folio_account_reference_display.presence || @booking.confirmation_token, path: hotel_folio_path(current_hotel, @booking, origin: "folios") },
          { label: "Folio Ledger" }
        )
      else
        override_breadcrumbs(
          { label: "Operations" },
          { label: "Bookings", path: hotel_bookings_path(current_hotel) },
          { label: @booking.confirmation_token, path: hotel_booking_path(current_hotel, @booking) },
          { label: "Folio Ledger" }
        )
      end
    end

    def authorize_view_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end

    def authorize_manage_folio_windows!
      allowed = current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
        current_user.has_permission?("manage_folio_windows", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end

    def authorize_manage_folio_movements!
      allowed = current_user.respond_to?(:superadmin?) && current_user.superadmin? ||
        current_user.has_permission?("manage_folio_movements", hotel: current_hotel)
      raise Pundit::NotAuthorizedError unless allowed
    end

    def folio_window_params
      params.fetch(:booking_folio, {}).permit(:name, :folio_type, :payer_type, :payer_id, :currency, :reason, :is_primary, :set_folio_as_primary_reason)
    end

    def folio_operation_params
      params.fetch(:folio_operation, {}).permit(:target_folio_id, :reason)
    end

    def folio_origin_params
      params[:origin] == "folios" || params[:folio_origin] == "folios" ? { origin: "folios" } : {}
    end
  end
end
