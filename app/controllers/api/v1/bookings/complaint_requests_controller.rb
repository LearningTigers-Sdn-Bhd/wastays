class Api::V1::Bookings::ComplaintRequestsController < Api::V1::BaseController
  before_action :set_booking

  def create
    @complaint_request = @booking.complaint_requests.build(complaint_params)
    @complaint_request.status ||= "pending"
    @complaint_request.requested_at ||= Time.current

    if @complaint_request.save
      render json: {
        message: "Complaint request created successfully.",
        complaint_request: @complaint_request
      }, status: :created
    else
      render json: {
        error: "Failed to create complaint request",
        details: @complaint_request.errors.full_messages
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

  def complaint_params
    params.require(:complaint_request).permit(:complaint_details, :external_id, :metadata)
  end
end
