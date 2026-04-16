class Public::PaymentMocksController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @quote = BookingQuote.find_by!(token: params[:quote_token])
  end

  def update
    @quote = BookingQuote.find_by!(token: params[:quote_token])
    result = confirm_booking(@quote, guest_details_params)

    if result.success? && result.booking
      redirect_to booking_path(result.booking.confirmation_token), notice: "Payment successful!"
    else
      redirect_to quote_path(@quote.token), alert: result.message.presence || "Payment failed. Please review your details and try again."
    end
  end

  private

  def confirm_booking(quote, guest_details)
    guest_details = guest_details.to_h.symbolize_keys

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
        external_reference: "curlec_evt_#{SecureRandom.hex(8)}"
      }
    ).call
  end

  def guest_details_params
    params.require(:guest_details).permit(:name, :email, :phone, :government_id, :gender, :country, :document_type)
  end
end
