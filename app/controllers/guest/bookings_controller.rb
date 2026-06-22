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
    pdf_bytes = InvoicePdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def e_invoice
    @booking = current_guest.bookings.find(params[:id])
    submission = @booking.e_invoice_submissions.guest_facing.valid.recent_first.first
    raise ActiveRecord::RecordNotFound unless submission

    pdf_bytes = EInvoicePdfService.new(@booking, submission: submission).generate
    send_data pdf_bytes,
      filename: "wastays-e-invoice-#{submission.internal_id || @booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end
end
