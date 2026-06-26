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

    if corporate_ar_webhook?(temp_payload)
      return handle_corporate_ar_webhook(gateway, raw_payload, temp_payload, event)
    end

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

    adapter = Payments::GatewayRegistry.fetch(gateway:, setting:)

    # 2. Verify signature
    signature = request.headers["X-Gateway-Signature"] || request.headers["X-Razorpay-Signature"]
    unless adapter.verify_webhook(payload: raw_payload, signature: signature)
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
        safely_record_transaction do
          Payments::TransactionRecorder.record_webhook(
            quote: quote,
            gateway: gateway,
            webhook_payload: temp_payload,
            processed_payload: processed_payload,
            booking: confirm_result.booking
          )
        end
        event.update!(status: "processed", processed_at: Time.current)
        head :ok
      else
        safely_record_transaction do
          Payments::TransactionRecorder.record_webhook(
            quote: quote,
            gateway: gateway,
            webhook_payload: temp_payload,
            processed_payload: processed_payload,
            status: "failed"
          )
        end
        event.update!(status: "failed", error_message: confirm_result.message)
        render json: { error: confirm_result.message }, status: :unprocessable_content
      end
    else
      safely_record_transaction do
        Payments::TransactionRecorder.record_webhook(
          quote: quote,
          gateway: gateway,
          webhook_payload: temp_payload,
          processed_payload: processed_payload
        )
      end
      event.update!(status: "processed", processed_at: Time.current)
      head :ok
    end
  rescue => e
    Rails.logger.error "Webhook Error: #{e.message}"
    event.update!(status: "failed", error_message: e.message) if defined?(event)
    head :internal_server_error
  end

  private

  def corporate_ar_webhook?(payload)
    notes = payload.dig(:payload, :payment, :entity, :notes) || {}
    notes[:payment_context].to_s == "corporate_ar" && notes[:corporate_ar_payment_intent_id].present?
  end

  def handle_corporate_ar_webhook(gateway, raw_payload, temp_payload, event)
    notes = temp_payload.dig(:payload, :payment, :entity, :notes) || {}
    intent = CorporateArPaymentIntent.find(notes[:corporate_ar_payment_intent_id])
    setting = intent.hotel.effective_payment_setting(gateway)

    unless setting
      event.update!(status: "failed", error_message: "No active payment setting for gateway #{gateway}")
      return head :forbidden
    end

    adapter = Payments::GatewayRegistry.fetch(gateway:, setting:)
    signature = request.headers["X-Gateway-Signature"] || request.headers["X-Razorpay-Signature"]
    unless adapter.verify_webhook(payload: raw_payload, signature: signature)
      event.update!(status: "failed", error_message: "Invalid signature")
      return head :unauthorized
    end

    processed_payload = adapter.handle_webhook(payload: temp_payload)
    result = CorporateArPayments::ProcessWebhook.call(
      intent: intent,
      gateway: gateway,
      processed_payload: processed_payload,
      webhook_payload: temp_payload
    )

    if result.success?
      event.update!(status: "processed", processed_at: Time.current)
      head :ok
    else
      event.update!(status: "failed", error_message: result.error)
      render json: { error: result.error }, status: :unprocessable_content
    end
  end

  def safely_record_transaction
    yield
  rescue StandardError => e
    Rails.logger.error("Webhook payment transaction logging failed: #{e.message}")
  end
end
