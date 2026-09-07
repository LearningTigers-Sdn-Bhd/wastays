class Guest::BookingsController < Guest::BaseController
  before_action :authenticate_guest!
  BOOKING_STATUSES = %w[pending confirmed checked_in completed cancelled].freeze

  def index
    @refund_policy = RefundPolicy.first
    @search_query = params[:q].to_s.strip
    @status_filter = params[:status].to_s.strip
    @status_options = BOOKING_STATUSES

    scope = current_guest.bookings.includes(:hotel, :refund_request)

    if @search_query.present?
      scope = scope.joins(:hotel).where(
        "hotels.name ILIKE :query OR bookings.confirmation_token ILIKE :query",
        query: "%#{@search_query}%"
      )
    end

    if @status_filter.present? && @status_options.include?(@status_filter)
      scope = @status_filter == "confirmed" ? scope.where(status: %w[confirmed no_show_detected]) : scope.where(status: @status_filter)
    end

    @all_bookings = scope.order(check_in: :desc, id: :desc)
    @pagy, @bookings = pagy(:offset, @all_bookings, limit: 25)
  end

  def show
    @refund_policy = RefundPolicy.first
    @booking = current_guest.bookings.find(params[:id])
    append_breadcrumb @booking.confirmation_token.upcase, guest_booking_path(@booking)

    assigned_rooms = @booking.booking_rooms.where.not(room_number: [ nil, "" ])
    @room_statuses = if assigned_rooms.any?
      RoomStatus.where(
        hotel_id: @booking.hotel_id,
        room_type_id: assigned_rooms.select(:room_type_id),
        room_number: assigned_rooms.select(:room_number)
      ).index_by { |rs| [ rs.room_type_id, rs.room_number ] }
    else
      {}
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def receipt
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = Reports::Bookings::GenerateConfirmation.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-receipt-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def invoice
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = ::Reports::Bookings::GeneratePrimaryGuestInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    redirect_to guest_bookings_path, alert: "No finalized guest invoice is available for this booking."
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  # The guest is signed in, so the group is reached through a room they own rather than
  # through a code they were sent.
  def voucher_pack
    booking = current_guest.bookings.includes(:group_booking).find(params[:id])
    group_booking = booking.group_booking
    return redirect_to guest_booking_path(booking), alert: "This booking is not part of a group." if group_booking.blank?

    send_data Reports::Bookings::GenerateVoucherPack.new(group_booking).generate,
      filename: "wastays-vouchers-#{group_booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue Reports::Bookings::GenerateVoucherPack::EmptyGroupError
    redirect_to guest_booking_path(booking), alert: "This group has no rooms to print."
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  # A room in a group reports the group's position, because that is the position anyone
  # settles.
  def summary
    booking = current_guest.bookings.includes(:group_booking).find(params[:id])
    subject = booking.group_booking || booking
    pdf_bytes = if subject.is_a?(GroupBooking)
      Reports::Bookings::GenerateBookingSummary.new(group_booking: subject).generate
    else
      Reports::Bookings::GenerateBookingSummary.new(booking: subject).generate
    end

    send_data pdf_bytes,
      filename: "wastays-booking-summary-#{subject.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def toggle_dnd
    @booking = current_guest.bookings.find(params[:id])
    result = Guest::ToggleDndService.new(booking: @booking).call

    if result.success?
      redirect_to guest_booking_path(@booking), notice: result.message
    else
      redirect_to guest_booking_path(@booking), alert: result.error
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def e_invoice
    @booking = current_guest.bookings.find(params[:id])
    submission = selected_guest_e_invoice_submission(@booking)
    raise ActiveRecord::RecordNotFound unless submission

    pdf_bytes = EInvoicePdfService.new(@booking, submission: submission).generate
    send_data pdf_bytes,
      filename: "wastays-e-invoice-#{submission.internal_id || @booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def request_e_invoice
    @booking = current_guest.bookings.find(params[:id])

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

    existing_pending = @booking.pending_guest_e_invoice_submission

    if existing_pending
      return respond_to_e_invoice_request_error("Your e-invoice is already being prepared. You will receive it shortly.", :accepted)
    end

    EInvoice::AutoIssueJob.perform_later(@booking.id, requested_by_guest: true)

    respond_to do |format|
      format.html do
        redirect_to guest_booking_path(@booking),
          notice: "Your e-invoice request has been submitted. You will receive it shortly."
      end
      format.json do
        render json: {
          status: "queued",
          message: "Your e-invoice request has been submitted. We are preparing it now."
        }, status: :accepted
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def status_e_invoice
    @booking = current_guest.bookings.find(params[:id])
    render json: e_invoice_status_payload(@booking)
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
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
        download_url: e_invoice_guest_booking_path(booking)
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
      format.html { redirect_to guest_booking_path(@booking), alert: message }
      format.json { render json: { status: "failed", message: message }, status: status }
    end
  end
end
