class Admin::ReconciliationsController < Admin::BaseController
  def index
    @events = WebhookEvent.order(created_at: :desc)
    @events = @events.where(status: params[:status]) if params[:status].present?
    @events = @events.where(gateway: params[:gateway]) if params[:gateway].present?
  end

  def show
    @event = WebhookEvent.find(params[:id])
  end

  def retry
    @event = WebhookEvent.find(params[:id])
    
    payload = @event.payload.symbolize_keys
    quote_token = payload.dig(:metadata, :quote_token)

    confirm_result = BookingEngine::ConfirmBooking.new(
      quote_token: quote_token,
      payment_details: {
        guest_name: payload.dig(:metadata, :guest_name),
        guest_email: payload.dig(:metadata, :guest_email),
        guest_phone: payload.dig(:metadata, :guest_phone),
        external_reference: payload[:id]
      }
    ).call

    if confirm_result.success?
      @event.update!(status: 'processed', processed_at: Time.current, error_message: nil)
      redirect_to admin_reconciliations_path, notice: "Confirmation retried successfully."
    else
      @event.update!(status: 'failed', error_message: confirm_result.message)
      redirect_to admin_reconciliation_path(@event), alert: "Retry failed: #{confirm_result.message}"
    end
  end

  def resolve
    @event = WebhookEvent.find(params[:id])
    @event.update!(status: 'processed', error_message: "Manually resolved by #{current_user.name}")
    redirect_to admin_reconciliations_path, notice: "Event marked as resolved."
  end
end
