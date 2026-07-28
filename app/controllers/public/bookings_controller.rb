class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    booking = Booking.with_confirmation_token(params[:id]).first!
    @booking = Public::BookingPresenter.new(booking, view_context)
    @hotel = Public::HotelPresenter.new(@booking.hotel, view_context)
    @booking_rooms = @booking.booking_rooms
    @display_currency = DisplayCurrencyResolver.new(params: params, cookies: cookies, request: request).call
    pre_checkin_result = GuestArrival::StartPreCheckin.new(booking).call
    @pre_checkin = pre_checkin_result.pre_checkin if pre_checkin_result.success?
    @qr_data_url = Concierge::QrSvg.data_url(@booking.confirmation_token)
  end

  def receipt
    confirmation
  end

  def confirmation
    @booking = Booking.with_confirmation_token(params[:id]).first!
    pdf_bytes = ReceiptPdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-booking-confirmation-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  def invoice
    @booking = Booking.with_confirmation_token(params[:id]).first!
    pdf_bytes = ::Reports::Bookings::GeneratePrimaryGuestInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    head :not_found
  end

  def voucher
    @booking = Booking.with_confirmation_token(params[:id]).first!
    pdf_bytes = VoucherPdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-voucher-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  private
end
