class Api::V1::AiConcierge::InquiriesController < Api::V1::BaseController
  def create
    authorize_hotel!(params[:hotel_id])
    return if performed?

    if inquiry_params[:message].blank?
      render json: { error: "Message is required" }, status: :unprocessable_content
      return
    end

    hotel = hotel_scope.includes(:property_policy, room_types: :room_rates).find(params[:hotel_id])
    result = AiConciergeV3::InquiryResponder.new(
      hotel: hotel,
      message: inquiry_params[:message],
      phone: inquiry_params[:phone]
    ).call

    if result.success?
      render json: result.payload
    else
      render json: { error: result.error }, status: result.status
    end
  end

  private

  def inquiry_params
    params.permit(:message, :phone)
  end
end
