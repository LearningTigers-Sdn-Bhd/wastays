# frozen_string_literal: true

class HotelPortal::Bookings::FoliosController < HotelPortal::BaseController
  before_action :authorize_view_bookings!

  def show
    @booking = current_hotel.bookings.includes(booking_folio: [ :folio_transactions, :folio_forecasted_charges ]).find(params[:id])
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    render "hotel_portal/bookings/folio"
  end

  def invoice
    @booking = current_hotel.bookings
      .includes(booking_folio: :folio_transactions, booking_rooms: :room_type)
      .find(params[:id])

    folio = @booking.booking_folio
    unless folio&.status == "closed"
      redirect_to hotel_booking_path(current_hotel, @booking),
        alert: "Folio invoice is only available for checked-out bookings with a closed folio."
      return
    end

    pdf_bytes = FolioInvoicePdfService.new(@booking).generate
    filename  = "folio-invoice-#{@booking.formatted_invoice_number || @booking.confirmation_token}.pdf"

    respond_to do |format|
      format.pdf do
        send_data pdf_bytes, filename: filename, type: "application/pdf", disposition: "inline"
      end
      format.html do
        send_data pdf_bytes, filename: filename, type: "application/pdf", disposition: "attachment"
      end
    end
  end

  private

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end
end
