# frozen_string_literal: true

class Api::V1::QuotesController < Api::V1::BaseController
  def create
    authorize_hotel!(params[:hotel_id])
    return if performed?

    result = BookingEngine::CreateQuote.new(quote_params).call

    if result.success?
      presenter = Public::QuotePresenter.new(result.quote, view_context)
      render json: {
        success: true,
        quote_token: presenter.token,
        booking_url: presenter.public_booking_url,
        total_amount: presenter.total_amount,
        currency: presenter.currency,
        expires_at: presenter.expires_at
      }, status: :created
    else
      render json: { success: false, error: result.message }, status: :unprocessable_entity
    end
  end

  def show
    quote = BookingQuote.find_by!(token: params[:id])
    authorize_hotel!(quote.hotel_id)
    return if performed?

    render json: quote.as_json(include: :booking_quote_items)
  end

  private

  def quote_params
    params.permit(:hotel_id, :room_type_id, :check_in, :check_out, :adults, :children, :room_count, :guest_name, :guest_email, :guest_phone, :special_requests)
  end
end
