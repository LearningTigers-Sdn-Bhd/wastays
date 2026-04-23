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
      render json: { errors: @housekeeping_request.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_booking
    @booking = booking_scope.find_by(confirmation_token: params[:booking_id]) || booking_scope.find(params[:booking_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Booking not found" }, status: :not_found
  end

  def housekeeping_params
    params.require(:housekeeping_request).permit(:request_details, :external_id, :metadata)
  end
end
