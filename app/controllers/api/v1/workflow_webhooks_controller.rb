class Api::V1::WorkflowWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    # Find booking by confirmation token or a specialized webhook token if we added one
    # For now, we'll assume the external system sends our confirmation_token
    booking = Booking.find_by!(confirmation_token: params[:booking_token])

    result = GuestArrival::SyncWorkflowEvent.new(booking, webhook_params).call

    if result.success?
      head :ok
    else
      render json: { error: result.message }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue => e
    Rails.logger.error "Workflow Webhook Error: #{e.message}"
    head :internal_server_error
  end

  private

  def webhook_params
    params.permit(:event_type, data: {})
  end
end
