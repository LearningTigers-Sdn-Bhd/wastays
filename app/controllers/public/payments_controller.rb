# frozen_string_literal: true

class Public::PaymentsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)
  skip_before_action :verify_authenticity_token, only: :verify

  def checkout_session
    quote = BookingQuote.find_by!(token: params[:quote_token])

    result = Payments::InitializeCheckout.new(
      quote: quote,
      gateway: params[:gateway],
      guest_details: guest_details_params.to_h,
      callback_url: verify_payment_url(quote_token: quote.token, gateway: params[:gateway])
    ).call

    if result.success?
      render json: result.payload
    else
      render json: { error: result.error }, status: :unprocessable_content
    end
  end

  def verify
    quote = BookingQuote.find_by!(token: params[:quote_token])
    gateway = params[:gateway].presence || quote.hotel.checkout_payment_gateway || "razorpay"

    result = Payments::ProcessVerification.new(
      quote: quote,
      gateway: gateway,
      payment_response: payment_response_params,
      guest_details: guest_details_params.to_h
    ).call

    if result.success?
      redirect_to booking_path(result.booking.confirmation_token), notice: "Payment successful!"
    else
      redirect_to quote_path(quote.token), alert: result.error
    end
  end

  private

  def guest_details_params
    params.fetch(:guest_details, {}).permit(
      :name, :email, :phone, :government_id, :gender, :city, :country, :document_type, :date_of_birth, :marketing_consent, :privacy_consent, :special_requests
    )
  end

  def payment_response_params
    from_nested = params.fetch(:payment_response, {}).permit(:razorpay_payment_id, :razorpay_order_id, :razorpay_signature).to_h
    from_redirect = params.permit(:razorpay_payment_id, :razorpay_order_id, :razorpay_signature).to_h

    from_nested.merge(from_redirect).symbolize_keys
  end
end
