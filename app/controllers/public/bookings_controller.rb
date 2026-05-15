class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @booking = Booking.find_by!(confirmation_token: params[:id])
    @hotel = @booking.hotel
    @booking_rooms = @booking.booking_rooms
    @pre_checkin = @booking.pre_checkin || @booking.create_pre_checkin!(
      status: "pending",
      document_status: "pending",
      signature_status: "pending"
    )
    @qr_svg = Concierge::QrSvg.for(@booking.confirmation_token).html_safe
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
