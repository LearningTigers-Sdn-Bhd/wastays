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
    submission = selected_guest_e_invoice_submission(@booking)
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
      return respond_to_e_invoice_request_error("This booking's payment has not concluded yet.")
    end

    unless @booking.e_invoice_requestable?
      return respond_to_e_invoice_request_error("E-invoice requests are only available within the same calendar month as the payment.")
    end

    if @booking.e_invoice_already_issued?
      return respond_to_e_invoice_request_error("An e-invoice has already been issued for this booking.")
    end

    existing_pending = @booking.pending_guest_e_invoice_submission

    if existing_pending
      return respond_to_e_invoice_request_error("Your e-invoice is already being prepared. You will receive it shortly.", :accepted)
    end

    EInvoice::AutoIssueJob.perform_later(@booking.id, requested_by_guest: true)

    respond_to do |format|
      format.html do
        redirect_to booking_path(@booking.confirmation_token),
          notice: "Your e-invoice request has been submitted. You will receive it shortly."
      end
      format.json do
        render json: {
          status: "queued",
          message: "Your e-invoice request has been submitted. We are preparing it now."
        }, status: :accepted
      end
    end
  end

  def status_e_invoice
    @booking = Booking.find_by!(confirmation_token: params[:id])
    render json: e_invoice_status_payload(@booking)
  end

  private

  def selected_guest_e_invoice_submission(booking)
    return booking.latest_ready_guest_e_invoice_submission if params[:submission_id].blank?

    booking.e_invoice_submissions.guest_facing.valid.find_by(id: params[:submission_id])
  end

  def e_invoice_status_payload(booking)
    if (submission = booking.latest_ready_guest_e_invoice_submission)
      {
        status: "ready",
        message: ready_e_invoice_message(submission),
        document_label: submission.document_type_label,
        download_url: e_invoice_booking_path(booking.confirmation_token)
      }
    elsif (submission = booking.latest_pending_guest_e_invoice_submission)
      {
        status: "processing",
        message: "We are preparing your e-invoice with LHDN now.",
        document_label: submission.document_type_label,
        download_url: nil
      }
    elsif (submission = booking.latest_failed_guest_e_invoice_submission)
      {
        status: "failed",
        message: submission.error_message.presence || "We could not generate the e-invoice yet. Our hotel team can help retry it.",
        document_label: submission.document_type_label,
        download_url: nil
      }
    else
      {
        status: "idle",
        message: "No guest e-invoice request has been submitted yet.",
        document_label: nil,
        download_url: nil
      }
    end
  end

  def ready_e_invoice_message(submission)
    if submission.adjustment?
      "Your updated e-invoice is ready."
    else
      "Your e-invoice is ready."
    end
  end

  def respond_to_e_invoice_request_error(message, status = :unprocessable_entity)
    respond_to do |format|
      format.html { redirect_to booking_path(@booking.confirmation_token), alert: message }
      format.json { render json: { status: "failed", message: message }, status: status }
    end
  end
end
