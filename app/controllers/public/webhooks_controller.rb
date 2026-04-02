class Public::WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    gateway = params[:gateway]

    # Pre-parse payload to find external ID and quote_token
    request.body.rewind
    raw_payload = request.body.read
    temp_payload = JSON.parse(raw_payload, symbolize_names: true)

    external_id = temp_payload[:id]
    quote_token = temp_payload.dig(:metadata, :quote_token)

    # 1. Log the incoming event
    event = WebhookEvent.find_or_initialize_by(gateway: gateway, external_id: external_id)
    event.assign_attributes(payload: temp_payload, status: "pending")
    event.save!

    unless quote_token
      event.update!(status: "failed", error_message: "Missing quote_token in metadata")
      return head :bad_request
    end

    quote = BookingQuote.find_by!(token: quote_token)
    hotel = quote.hotel
    setting = hotel.effective_payment_setting(gateway)

    unless setting
      event.update!(status: "failed", error_message: "No active payment setting for gateway #{gateway}")
      return head :forbidden
    end

    adapter = payment_adapter(gateway, setting)

    # 2. Verify signature
    unless adapter.verify_webhook(payload: raw_payload, signature: request.headers["X-Gateway-Signature"])
      event.update!(status: "failed", error_message: "Invalid signature")
      return head :unauthorized
    end

    # 3. Process payload
    processed_payload = adapter.handle_webhook(payload: temp_payload)

    if processed_payload[:status] == "captured"
      metadata = processed_payload[:metadata] || {}
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
          external_reference: processed_payload[:external_reference]
        }
      ).call

      if confirm_result.success?
        event.update!(status: "processed", processed_at: Time.current)
        head :ok
      else
        event.update!(status: "failed", error_message: confirm_result.message)
        render json: { error: confirm_result.message }, status: :unprocessable_content
      end
    else
      event.update!(status: "processed", processed_at: Time.current)
      head :ok
    end
  rescue => e
    Rails.logger.error "Webhook Error: #{e.message}"
    event.update!(status: "failed", error_message: e.message) if defined?(event)
    head :internal_server_error
  end

  private

  def payment_adapter(gateway, setting)
    case gateway
    when "curlec"
      Payments::GatewayAdapters::Curlec.new(setting)
    else
      raise "Unsupported Gateway: #{gateway}"
    end
  end
end
