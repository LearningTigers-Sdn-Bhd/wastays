class Guest::RefundRequestsController < Guest::BaseController
  before_action :authenticate_guest!
  before_action :set_booking, only: [ :new, :create ]
  before_action :set_refund_mode, only: [ :new, :create ]
  before_action :set_refund_preview, only: [ :new, :create ]
  before_action :set_booking_for_show, only: [ :show ]
  before_action :set_form_breadcrumbs, only: [ :new, :create ]
  before_action :set_show_breadcrumbs, only: [ :show ]
  RETURN_TO_LIST = "list".freeze
  RETURN_TO_DETAILS = "details".freeze
  RETURN_TO_REFUND = "refund".freeze

  def index
    @search_query = params[:q].to_s.strip
    @status_options = if RefundRequest.respond_to?(:statuses)
      RefundRequest.statuses.keys
    else
      %w[pending approved completed rejected]
    end
    @status_filter = params[:status].to_s.strip

    scope = current_guest.bookings
      .includes(:hotel, :refund_request)
      .joins(:refund_request)

    if @search_query.present?
      scope = scope.joins(:hotel).where(
        "hotels.name ILIKE :query OR bookings.confirmation_token ILIKE :query OR bookings.reservation_reference ILIKE :query",
        query: "%#{@search_query}%"
      )
    end

    if @status_filter.present? && @status_options.include?(@status_filter)
      scope = scope.where(refund_requests: { status: @status_filter })
    end

    @all_bookings = scope.order("refund_requests.created_at DESC", id: :desc).distinct
    @pagy, @bookings = pagy(:offset, @all_bookings, limit: 25)
  end

  def new
    @return_to = normalized_return_to
    @refund_request = Refunds::Draft.new(booking: @booking).call
  end

  def show
    @refund_request = @booking.refund_request
  end

  def create
    @return_to = normalized_return_to
    refund_params = Refunds::RequestParams.new(params).call

    result = Refunds::SubmitRequest.new(booking: @booking, params: refund_params, mode: @refund_mode).call

    if result.success?
      redirect_to success_redirect_path, notice: success_message, status: :see_other
    else
      @refund_request = RefundRequest.new(refund_params.except(:refund_amount))
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_booking
    @booking = current_guest.bookings.find_by(id: params[:booking_id])
    return if @booking

    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def set_booking_for_show
    @booking = current_guest.bookings
      .includes(:hotel, :refund_request)
      .joins(:refund_request)
      .find_by("refund_requests.id = ?", params[:id])
    return if @booking

    redirect_to guest_refund_requests_path, alert: "Refund request not found."
  end

  # A guest in house asks without cancelling; any other booking goes through
  # the cancel-and-refund path, which also explains why a booking cannot.
  def set_refund_mode
    return unless @booking

    @refund_policy = RefundPolicy.first
    @refund_mode = Refunds::ModeFor.new(booking: @booking, policy: @refund_policy).call || :pre_stay
  end

  def set_refund_preview
    return unless @booking && @refund_mode == :pre_stay && @refund_policy

    @refund_percentage = @refund_policy.refund_percentage
    @estimated_refund_amount = (@booking.total_amount * (@refund_percentage / 100.0)).round(2)
  end

  def set_form_breadcrumbs
    append_booking_breadcrumb(@booking)
    append_breadcrumb "Request Refund"
  end

  def set_show_breadcrumbs
    append_booking_breadcrumb(@booking)
    append_breadcrumb "Refund Details"
  end

  def normalized_return_to
    value = params[:return_to].to_s
    return RETURN_TO_LIST if value == RETURN_TO_LIST
    return RETURN_TO_REFUND if value == RETURN_TO_REFUND

    RETURN_TO_DETAILS
  end

  def success_message
    return "We have your refund request. The property will reply to you." if @refund_mode == :post_stay

    "Refund request submitted. Your booking has been cancelled."
  end

  def success_redirect_path
    return guest_bookings_path if @return_to == RETURN_TO_LIST
    return guest_refund_request_path(@booking.refund_request) if @return_to == RETURN_TO_REFUND

    guest_booking_path(@booking)
  end
end
