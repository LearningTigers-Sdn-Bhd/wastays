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
      scope = @status_filter == "confirmed" ? scope.where(status: %w[confirmed review_no_show]) : scope.where(status: @status_filter)
    end

    @all_bookings = scope.order(check_in: :desc)
    @bookings = @all_bookings.page(params[:page]).per(25)
  end

  def show
    @refund_policy = RefundPolicy.first
    @booking = current_guest.bookings.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def receipt
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = ReceiptPdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-receipt-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def invoice
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = ::Reports::Bookings::GenerateInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    redirect_to guest_bookings_path, alert: "Invoice is only available after checkout."
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

  def respond_to_e_invoice_request_error(message, status = :unprocessable_entity)
    respond_to do |format|
      format.html { redirect_to guest_booking_path(@booking), alert: message }
      format.json { render json: { status: "failed", message: message }, status: status }
    end
  end
end
