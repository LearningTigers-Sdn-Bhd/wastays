class Guest::RefundRequestsController < Guest::BaseController
  before_action :authenticate_guest!
  before_action :set_booking, only: [ :new, :create ]
  before_action :set_refund_preview, only: [ :new, :create ]
  before_action :set_booking_for_show, only: [ :show ]
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
        "hotels.name ILIKE :query OR bookings.confirmation_token ILIKE :query",
        query: "%#{@search_query}%"
      )
    end

    if @status_filter.present? && @status_options.include?(@status_filter)
      scope = scope.where(refund_requests: { status: @status_filter })
    end

    @all_bookings = scope.order("refund_requests.created_at DESC").distinct
    @bookings = @all_bookings.page(params[:page]).per(25)
  end

  def new
    @return_to = normalized_return_to
    if @booking.refund_request&.rejected?
      @refund_request = RefundRequest.new(
        reason: @booking.refund_request.reason,
        bank_name: @booking.refund_request.bank_name,
        account_holder_name: @booking.refund_request.account_holder_name,
        account_number: @booking.refund_request.account_number,
        account_type: @booking.refund_request.account_type
      )
    else
      @refund_request = RefundRequest.new
    end
    @presenter = RefundRequestPresenter.new(@refund_request)
  end

  def show
    @refund_request = @booking.refund_request
  end

  def create
    @return_to = normalized_return_to
    @refund_request = RefundRequest.new(refund_request_params)

    result = Refunds::SubmitRequest.new(
      booking: @booking,
      params: refund_request_params
    ).call

    if result.success?
      redirect_to success_redirect_path, notice: "Refund request submitted. Your booking has been cancelled.", status: :see_other
    else
      @presenter = RefundRequestPresenter.new(@refund_request)
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
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

  def set_refund_preview
    @refund_policy = RefundPolicy.first
    return unless @refund_policy

    @refund_percentage = @refund_policy.refund_percentage
    @estimated_refund_amount = (@booking.total_amount * (@refund_percentage / 100.0)).round(2)
  end

  def refund_request_params
    params.require(:refund_request).permit(:reason, :bank_name, :account_holder_name, :account_number, :account_type)
  end

  def normalized_return_to
    value = params[:return_to].to_s
    return RETURN_TO_LIST if value == RETURN_TO_LIST
    return RETURN_TO_REFUND if value == RETURN_TO_REFUND

    RETURN_TO_DETAILS
  end

  def success_redirect_path
    return guest_bookings_path if @return_to == RETURN_TO_LIST
    return guest_refund_request_path(@booking.refund_request) if @return_to == RETURN_TO_REFUND

    guest_booking_path(@booking)
  end
end
