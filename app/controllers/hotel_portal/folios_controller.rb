# frozen_string_literal: true

module HotelPortal
  class FoliosController < BaseController
    before_action :authorize_view_bookings!
    before_action :set_booking, only: [ :show, :invoice, :ledger, :issue_adjustment ]

    def index
      @folio_index = HotelPortal::Folios::IndexPresenter.new(
        hotel: current_hotel,
        params: params
      )
      render "hotel_portal/folios/index/index"
    end

    def show
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      @folio_show = HotelPortal::Folios::ShowPresenter.new(booking: @booking, hotel: current_hotel, user: current_user)
      @adjustment_preview = EInvoice::IssueAdjustment.preview(@booking)
      set_navigation_context
      set_breadcrumbs
      render "hotel_portal/folios/show/index"
    end

    def invoice
      unless @booking.booking_folio&.status == "closed"
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Folio invoice is only available for checked-out bookings with a closed folio."
      end

      send_data ::Reports::Bookings::GenerateInvoice.new(booking: @booking, printed_by: current_user&.name).generate,
        filename: "folio-invoice-#{@booking.formatted_invoice_number || @booking.confirmation_token}.pdf",
        type: "application/pdf",
        disposition: request.format.pdf? ? "inline" : "attachment"
    end

    def ledger
      return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Booking has no folio." unless @booking.booking_folio

      ledger_report = ::Reports::Bookings::GenerateFolioLedger.new(booking: @booking, printed_by: current_user&.name)
      filename = "folio-ledger-#{@booking.formatted_folio_number.presence || @booking.confirmation_token}"

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

    def issue_adjustment
      result = EInvoice::IssueAdjustment.call(@booking)

      if result[:success]
        redirect_to hotel_e_invoice_submission_path(current_hotel, result[:submission]),
          notice: "Adjustment note is being prepared and sent to LHDN."
      elsif result[:skipped]
        redirect_to hotel_folio_path(current_hotel, @booking, origin: params[:origin]),
          alert: result[:message]
      else
        redirect_to hotel_folio_path(current_hotel, @booking, origin: params[:origin]),
          alert: result[:error] || "Unable to issue adjustment note right now."
      end
    end

    private

    def set_booking
      @booking = booking_scope.find(params[:booking_id])
    end

    def booking_scope
      current_hotel.bookings.includes(
        :e_invoice_submissions,
        { booking_rooms: :room_type },
        booking_folio: [ { folio_transactions: [ :user, :transaction_code ] }, :folio_forecasted_charges ]
      )
    end

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
          { label: @booking.formatted_folio_number.presence || @booking.confirmation_token, path: hotel_folio_path(current_hotel, @booking, origin: "folios") },
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
  end
end
