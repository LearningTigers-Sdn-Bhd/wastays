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
    pdf_bytes = Reports::Bookings::GenerateConfirmation.new(@booking).generate
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
    pdf_bytes = Reports::Bookings::GenerateVoucher.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-voucher-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  # A group organiser holds the group's own code; each guest holds their room's. Either one
  # reaches the pack, so the organiser can print the set from the link they were sent.
  def voucher_pack
    group_booking = resolve_group_booking!
    pdf_bytes = Reports::Bookings::GenerateVoucherPack.new(group_booking).generate
    send_data pdf_bytes,
      filename: "wastays-vouchers-#{group_booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue Reports::Bookings::GenerateVoucherPack::EmptyGroupError
    head :not_found
  end

  def summary
    subject = resolve_summary_subject!
    pdf_bytes = if subject.is_a?(GroupBooking)
      Reports::Bookings::GenerateBookingSummary.new(group_booking: subject).generate
    else
      Reports::Bookings::GenerateBookingSummary.new(booking: subject).generate
    end
    send_data pdf_bytes,
      filename: "wastays-booking-summary-#{subject.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  def e_invoice
    @booking = Booking.with_confirmation_token(params[:id]).first!
    submission = selected_guest_e_invoice_submission(@booking)
    raise ActiveRecord::RecordNotFound unless submission

    pdf_bytes = EInvoicePdfService.new(@booking, submission: submission).generate
    send_data pdf_bytes,
      filename: "wastays-e-invoice-#{submission.internal_id || @booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  def request_e_invoice
    @booking = Booking.with_confirmation_token(params[:id]).first!

    unless @booking.payment_concluded?
      return respond_to_e_invoice_request_error("This booking's payment has not concluded yet.")
    end

    unless @booking.e_invoice_requestable?
      return respond_to_e_invoice_request_error("E-invoice requests are only available within the same calendar month as the payment.")
    end

    if @booking.e_invoice_already_issued?
      return respond_to_e_invoice_request_error("An e-invoice has already been issued for this booking.")
    end

    # Say what is missing while the guest can still supply it, rather than
    # accepting the request and failing LHDN validation days later.
    missing = @booking.e_invoice_buyer_details_missing
    if missing.any?
      return respond_to_e_invoice_request_error(
        "We need your #{missing.to_sentence} before we can request the e-invoice. Please contact the hotel to update your details."
      )
    end

    if @booking.pending_guest_e_invoice_submission
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
    @booking = Booking.with_confirmation_token(params[:id]).first!
    render json: e_invoice_status_payload(@booking)
  end

  private

  # A room that belongs to a group reports the group's position, because that is the
  # position anyone settles.
  def resolve_summary_subject!
    booking = Booking.with_confirmation_token(params[:id]).includes(:group_booking).first
    return booking.group_booking || booking if booking

    GroupBooking.with_confirmation_token(params[:id]).first!
  end

  def resolve_group_booking!
    booking = Booking.with_confirmation_token(params[:id]).includes(:group_booking).first
    group_booking = booking&.group_booking
    return group_booking if group_booking
    raise ActiveRecord::RecordNotFound, "booking #{params[:id]} belongs to no group" if booking

    GroupBooking.with_confirmation_token(params[:id]).first!
  end
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

  def respond_to_e_invoice_request_error(message, status = :unprocessable_content)
    respond_to do |format|
      format.html { redirect_to booking_path(@booking.confirmation_token), alert: message }
      format.json { render json: { status: "failed", message: message }, status: status }
    end
  end
end
