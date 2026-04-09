class Admin::ReconciliationsController < Admin::BaseController
  def index
    base_scope = WebhookEvent.order(created_at: :desc)

    @summary_total_events = base_scope.count
    @summary_failed_events = base_scope.failed.count
    @summary_pending_events = base_scope.pending.count
    @summary_processed_events = base_scope.where(status: "processed").count
    @gateway_options = base_scope.reorder(nil).distinct.pluck(:gateway).compact.sort

    @events = base_scope
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

    metadata = payload[:metadata] || {}
    confirm_result = BookingEngine::ConfirmBooking.new(
      quote_token: quote_token,
      payment_details: {
        guest_name: metadata[:guest_name],
        guest_email: metadata[:guest_email],
        guest_phone: metadata[:guest_phone],
        government_id: metadata[:government_id],
        gender: metadata[:gender],
        country: metadata[:country],
        document_type: metadata[:document_type],
        external_reference: payload[:id]
      }
    ).call

    if confirm_result.success?
      @event.update!(status: "processed", processed_at: Time.current, error_message: nil)
      redirect_to admin_reconciliations_path, notice: "Confirmation retried successfully."
    else
      @event.update!(status: "failed", error_message: confirm_result.message)
      redirect_to admin_reconciliation_path(@event), alert: "Retry failed: #{confirm_result.message}"
    end
  end

  def resolve
    @event = WebhookEvent.find(params[:id])
    @event.update!(status: "processed", error_message: "Manually resolved by #{current_user.name}")
    redirect_to admin_reconciliations_path, notice: "Event marked as resolved."
  end
end
