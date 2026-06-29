class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    booking = Booking.find_by!(confirmation_token: params[:id])
    @booking = Public::BookingPresenter.new(booking, view_context)
    @hotel = Public::HotelPresenter.new(@booking.hotel, view_context)
    @booking_rooms = @booking.booking_rooms
    pre_checkin_result = GuestArrival::StartPreCheckin.new(booking).call
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
    pdf_bytes = ::Reports::Bookings::GenerateInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    head :not_found
  end

  def e_invoice
    @booking = Booking.find_by!(confirmation_token: params[:id])
    submission = @booking.ready_guest_e_invoice_submission
    raise ActiveRecord::RecordNotFound unless submission

    pdf_bytes = EInvoicePdfService.new(@booking, submission: submission).generate
    send_data pdf_bytes,
      filename: "wastays-e-invoice-#{submission.internal_id || @booking.confirmation_token}.pdf",
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

  def request_e_invoice
    @booking = Booking.find_by!(confirmation_token: params[:id])

    unless @booking.payment_concluded?
      return redirect_to booking_path(@booking.confirmation_token), alert: "This booking's payment has not concluded yet."
    end

    unless @booking.e_invoice_requestable?
      return redirect_to booking_path(@booking.confirmation_token), alert: "E-invoice requests are only available within the same calendar month as the payment."
    end

    if @booking.e_invoice_already_issued?
      return redirect_to booking_path(@booking.confirmation_token), alert: "An e-invoice has already been issued for this booking."
    end

    existing_pending = @booking.pending_guest_e_invoice_submission

    if existing_pending
      return redirect_to booking_path(@booking.confirmation_token),
        alert: "Your e-invoice is already being prepared. You will receive it shortly."
    end

    EInvoice::AutoIssueJob.perform_later(@booking.id, requested_by_guest: true)

    redirect_to booking_path(@booking.confirmation_token),
      notice: "Your e-invoice request has been submitted. You will receive it shortly."
  end

  private
end
