class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @booking = Booking.find_by!(confirmation_token: params[:id])
    @hotel = @booking.hotel
    @booking_rooms = @booking.booking_rooms
    pre_checkin_result = GuestArrival::StartPreCheckin.new(@booking).call
    @pre_checkin = pre_checkin_result.pre_checkin if pre_checkin_result.success?
    @qr_data_url = Concierge::QrSvg.data_url(@booking.confirmation_token)
  end

  def receipt
    @booking = Booking.find_by!(confirmation_token: params[:id])
    pdf_bytes = ReceiptPdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-receipt-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  def invoice
    @booking = Booking.find_by!(confirmation_token: params[:id])
    pdf_bytes = InvoicePdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  def voucher
    @booking = Booking.find_by!(confirmation_token: params[:id])
    pdf_bytes = VoucherPdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-voucher-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  private
end
