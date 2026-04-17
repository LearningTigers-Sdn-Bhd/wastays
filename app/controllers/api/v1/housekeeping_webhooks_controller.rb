class Api::V1::HousekeepingWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    booking = Booking.find_by!(confirmation_token: params[:booking_token])
    result = Housekeeping::SyncRequestEvent.new(booking, webhook_params).call

    if result.success?
      head :ok
    else
      render json: { error: result.message }, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue => e
    Rails.logger.error "Housekeeping Webhook Error: #{e.message}"
    head :internal_server_error
  end

  private

  def webhook_params
    params.permit(
      :date,
      :status,
      :requests,
      :external_id,
      data: {},
      requests: []
    ).to_h.deep_symbolize_keys
  end
end
