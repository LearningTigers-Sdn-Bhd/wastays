class Public::PaymentMocksController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @quote = BookingQuote.find_by!(token: params[:quote_token])
  end

  def update
    @quote = BookingQuote.find_by!(token: params[:quote_token])

    # Simulate Curlec webhook in background
    simulate_webhook(@quote, guest_details_params)

    # Wait for a moment to simulate network delay
    sleep 1

    # Redirect to booking show page
    # In a real app, we would poll or use a websocket to wait for the webhook confirmation
    # For MVP mock, we just predict the token
    confirmation_token = "WS-#{SecureRandom.alphanumeric(8).upcase}"
    # Wait for the webhook job to finish
    sleep 0.5

    booking = Booking.find_by(booking_quote_id: @quote.id)
    if booking
      redirect_to booking_path(booking.confirmation_token), notice: "Payment successful!"
    else
      # If webhook hasn't processed, we might need a processing page
      # For simplicity in mock, we'll try to find it again
      sleep 1
      booking = Booking.find_by(booking_quote_id: @quote.id)
      if booking
        redirect_to booking_path(booking.confirmation_token), notice: "Payment successful!"
      else
        redirect_to root_path, alert: "Payment processing... please check your email shortly."
      end
    end
  end

  private

  def simulate_webhook(quote, guest_details)
    guest_details = guest_details.to_h.symbolize_keys

    # We'll use a Thread to simulate an asynchronous webhook call from the gateway
    Thread.new do
      payload = {
        id: "curlec_evt_#{SecureRandom.hex(8)}",
        status: "captured",
        amount: quote.total_amount,
        currency: quote.currency,
        metadata: {
          quote_token: quote.token,
          guest_name: guest_details[:name],
          guest_email: guest_details[:email],
          guest_phone: guest_details[:phone],
          gender: guest_details[:gender],
          country: guest_details[:country],
          document_type: guest_details[:document_type]
        }
      }

      # Call our own webhook endpoint
      uri = URI.parse("http://localhost:3000/public/webhooks/curlec") # Adjust as needed
      # Note: In test environment this might fail if server isn't running
      # So we'll call the service directly instead for more robustness in mock
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
          external_reference: payload[:id]
        }
      ).call
    end
  end

  def guest_details_params
    params.require(:guest_details).permit(:name, :email, :phone, :government_id, :gender, :country, :document_type)
  end
end
