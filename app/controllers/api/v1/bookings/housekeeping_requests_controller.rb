class Api::V1::Bookings::HousekeepingRequestsController < Api::V1::BaseController
  before_action :set_booking

  def create
    @housekeeping_request = @booking.housekeeping_requests.build(housekeeping_params)
    @housekeeping_request.status ||= "pending"
    @housekeeping_request.requested_at ||= Time.current

    if @housekeeping_request.save
      render json: {
        message: "Housekeeping request created successfully.",
        housekeeping_request: @housekeeping_request
      }, status: :created
    else
      render json: {
        error: "Failed to create housekeeping request",
        details: @housekeeping_request.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_booking
    @booking = booking_scope.with_confirmation_token(params[:booking_id]).first || booking_scope.find_by(id: params[:booking_id])

    unless @booking
      render json: { error: "Booking not found or access denied" }, status: :not_found
    end
  end

  def housekeeping_params
    params.require(:housekeeping_request).permit(:request_details, :external_id, :metadata)
  end
end
