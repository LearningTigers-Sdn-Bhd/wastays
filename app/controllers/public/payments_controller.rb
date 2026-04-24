class Public::PaymentsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)
  skip_before_action :verify_authenticity_token, only: :verify

  def checkout_session
    quote = BookingQuote.find_by!(token: params[:quote_token])
    gateway = payment_gateway_param(quote)
    setting = quote.hotel.effective_payment_setting(gateway)
    return render json: { error: "Payment gateway is not configured." }, status: :unprocessable_content unless setting

    adapter = Payments::GatewayRegistry.fetch(gateway:, setting:)
    payload = adapter.create_checkout_session(
      amount: quote.total_amount,
      currency: quote.currency,
      description: "Booking payment for #{quote.hotel.name}",
      metadata: session_metadata(quote),
      callback_url: callback_url_for(quote, gateway)
    )

    render json: payload.merge(gateway: gateway)
  rescue Payments::GatewayRegistry::UnsupportedGatewayError => e
    render json: { error: e.message }, status: :bad_request
  rescue StandardError => e
    Rails.logger.error("Payment checkout session error: #{e.message}")
    render json: { error: "Unable to initialize payment at the moment." }, status: :unprocessable_content
  end

  def verify
    quote = BookingQuote.find_by!(token: params[:quote_token])
    gateway = payment_gateway_param(quote)
    setting = quote.hotel.effective_payment_setting(gateway)
    return redirect_to quote_path(quote.token), alert: "Payment gateway is not configured." unless setting

    adapter = Payments::GatewayRegistry.fetch(gateway:, setting:)
    verification = adapter.verify_client_callback(payment_response: payment_response_params)
    guest_details = guest_details_for_confirmation(verification[:metadata] || {})

    if verification[:status] == "captured"
      unless guest_details.present?
        return redirect_to quote_path(quote.token), alert: "Missing guest details for booking confirmation."
      end

      result = confirm_booking(quote, guest_details, verification[:external_reference])
      safely_record_transaction do
        Payments::TransactionRecorder.record_verification(
          quote: quote,
          gateway: gateway,
          payment_response: payment_response_params,
          verification_result: verification,
          booking: result.booking
        )
      end

      if result.success? && result.booking
        redirect_to booking_path(result.booking.confirmation_token), notice: "Payment successful!"
      else
        redirect_to quote_path(quote.token), alert: result.message.presence || "Payment verification passed, but booking confirmation failed."
      end
    else
      safely_record_transaction do
        Payments::TransactionRecorder.record_verification(
          quote: quote,
          gateway: gateway,
          payment_response: payment_response_params,
          verification_result: verification
        )
      end
      redirect_to quote_path(quote.token), alert: verification[:message].presence || "Payment verification failed."
    end
  rescue Payments::GatewayRegistry::UnsupportedGatewayError => e
    redirect_to quote_path(params[:quote_token]), alert: e.message
  rescue StandardError => e
    Rails.logger.error("Payment verification error: #{e.message}")
    redirect_to quote_path(params[:quote_token]), alert: "Unable to verify payment at the moment."
  end

  private

  def confirm_booking(quote, guest_details, external_reference)
    guest_details = guest_details.symbolize_keys

    BookingEngine::ConfirmBooking.new(
      quote_token: quote.token,
      payment_details: {
        guest_name: guest_details[:name],
        guest_email: guest_details[:email],
        guest_phone: guest_details[:phone],
        government_id: guest_details[:government_id],
        gender: guest_details[:gender],
        country: guest_details[:country],
        document_type: guest_details[:document_type],
        marketing_consent: guest_details[:marketing_consent],
        external_reference: external_reference
      }
    ).call
  end

  def session_metadata(quote)
    {
      quote_token: quote.token,
      guest_name: guest_details_params[:name],
      guest_email: guest_details_params[:email],
      guest_phone: guest_details_params[:phone],
      government_id: guest_details_params[:government_id],
      gender: guest_details_params[:gender],
      country: guest_details_params[:country],
      document_type: guest_details_params[:document_type],
      marketing_consent: guest_details_params[:marketing_consent]
    }
  end

  def callback_url_for(quote, gateway)
    verify_payment_url(quote_token: quote.token, gateway: gateway)
  end

  def payment_gateway_param(quote)
    params[:gateway].presence || quote.hotel.checkout_payment_gateway || "razorpay"
  end

  def guest_details_params
    params.require(:guest_details).permit(:name, :email, :phone, :government_id, :gender, :country, :document_type, :marketing_consent)
  end

  def guest_details_for_confirmation(metadata)
    return guest_details_params.to_h.symbolize_keys if params[:guest_details].present?

    metadata = metadata.to_h.symbolize_keys
    return if metadata.blank?

    {
      name: metadata[:guest_name] || metadata[:name],
      email: metadata[:guest_email] || metadata[:email],
      phone: metadata[:guest_phone] || metadata[:phone],
      government_id: metadata[:government_id],
      gender: metadata[:gender],
      country: metadata[:country],
      document_type: metadata[:document_type],
      marketing_consent: metadata[:marketing_consent]
    }.compact
  rescue ActionController::ParameterMissing
    nil
  end

  def payment_response_params
    from_nested = params.fetch(:payment_response, {}).permit(:razorpay_payment_id, :razorpay_order_id, :razorpay_signature).to_h
    from_redirect = params.permit(:razorpay_payment_id, :razorpay_order_id, :razorpay_signature).to_h

    from_nested.merge(from_redirect).symbolize_keys
  end

  def safely_record_transaction
    yield
  rescue StandardError => e
    Rails.logger.error("Payment transaction logging failed: #{e.message}")
  end
end
