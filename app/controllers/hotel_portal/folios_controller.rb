# frozen_string_literal: true

module HotelPortal
  class FoliosController < BaseController
    before_action :authorize_view_bookings!

    def show
      @booking = current_hotel.bookings.includes(
        :e_invoice_submissions,
        booking_folio: [ { folio_transactions: :user }, :folio_forecasted_charges ]
      ).find(params[:booking_id])
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      set_breadcrumbs
      render "hotel_portal/folios/show/index"
    end

    def invoice
      @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions, booking_rooms: :room_type).find(params[:booking_id])
      unless @booking.booking_folio&.status == "closed"
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Folio invoice is only available for checked-out bookings with a closed folio."
      end

      send_data FolioInvoicePdfService.new(@booking).generate,
        filename: "folio-invoice-#{@booking.formatted_invoice_number || @booking.confirmation_token}.pdf",
        type: "application/pdf",
        disposition: request.format.pdf? ? "inline" : "attachment"
    end

    private

    def set_breadcrumbs
      override_breadcrumbs(
        { label: "Operations" },
        { label: "Bookings", path: hotel_bookings_path(current_hotel) },
        { label: @booking.confirmation_token, path: hotel_booking_path(current_hotel, @booking) },
        { label: "Folio Ledger" }
      )
    end

    def authorize_view_bookings!
      raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
    end
  end
end
