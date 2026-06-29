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
    submission = @booking.ready_guest_e_invoice_submission
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
      return redirect_to guest_booking_path(@booking), alert: "This booking's payment has not concluded yet."
    end

    unless @booking.e_invoice_requestable?
      return redirect_to guest_booking_path(@booking), alert: "E-invoice requests are only available within the same calendar month as the payment."
    end

    if @booking.e_invoice_already_issued?
      return redirect_to guest_booking_path(@booking), alert: "An e-invoice has already been issued for this booking."
    end

    # Check for existing pending individual submission (duplicate request)
    existing_pending = @booking.pending_guest_e_invoice_submission

    if existing_pending
      return redirect_to guest_booking_path(@booking),
        alert: "Your e-invoice is already being prepared. You will receive it shortly."
    end

    EInvoice::AutoIssueJob.perform_later(@booking.id, requested_by_guest: true)

    redirect_to guest_booking_path(@booking),
      notice: "Your e-invoice request has been submitted. You will receive it shortly."
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end
end
