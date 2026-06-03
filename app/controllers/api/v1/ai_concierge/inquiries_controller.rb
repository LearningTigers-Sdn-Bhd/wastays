class Api::V1::AiConcierge::InquiriesController < Api::V1::BaseController
  def create
    hotel = authorize_hotel!(params[:hotel_id])
    return if performed?

    if inquiry_params[:message].blank?
      render json: { error: "Message is required" }, status: :unprocessable_content
      return
    end

    if inquiry_params[:phone].blank? && inquiry_params[:prospect_public_id].blank?
      render json: { error: "Phone or prospect_public_id is required for AI concierge conversations" }, status: :unprocessable_content
      return
    end

    hotel = hotel.class.includes(:property_policy, room_types: :room_rates).find(hotel.id)
    result = AiConciergeV3::Orchestration::InquiryResponder.new(
      hotel: hotel,
      message: inquiry_params[:message],
      phone: inquiry_params[:phone],
      prospect_public_id: inquiry_params[:prospect_public_id]
    ).call

    if result.success?
      render json: result.payload
    else
      render json: { error: result.error }, status: result.status
    end
  end

  private

  def inquiry_params
    source = params[:inquiry].presence || params[:ai_concierge].presence || params
    source.slice(:message, :phone, :prospect_public_id).permit(:message, :phone, :prospect_public_id)
  end
end
