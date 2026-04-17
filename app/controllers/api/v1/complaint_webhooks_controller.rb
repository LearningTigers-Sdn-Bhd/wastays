class Api::V1::ComplaintWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    booking = Booking.find_by!(confirmation_token: params[:booking_token])
    result = Complaints::SyncRequest.new(booking, webhook_params).call

    if result.success?
      head :ok
    else
      render json: { error: result.message }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue => e
    Rails.logger.error "Complaint Webhook Error: #{e.message}"
    head :internal_server_error
  end

  private

  def webhook_params
    params.permit(
      :date,
      :external_id,
      :complaint,
      :status,
      data: {}
    ).to_h.deep_symbolize_keys
  end
end
