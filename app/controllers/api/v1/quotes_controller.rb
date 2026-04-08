class Api::V1::QuotesController < Api::V1::BaseController
  def create
    authorize_hotel!(params[:hotel_id])
    return if performed?

    result = BookingEngine::CreateQuote.new(quote_params).call

    if result.success?
      render json: {
        success: true,
        quote_token: result.quote.token,
        booking_url: public_quote_url(result.quote.token),
        total_amount: result.quote.total_amount,
        currency: result.quote.currency,
        expires_at: result.quote.expires_at
      }, status: :created
    else
      render json: { success: false, error: result.message }, status: :unprocessable_entity
    end
  end

  def show
    # Quotes are public by token, but we check if the hotel belongs to the API key bearer
    quote = BookingQuote.find_by!(token: params[:id])
    authorize_hotel!(quote.hotel_id)
    return if performed?

    render json: quote.as_json(include: :booking_quote_items)
  end

  private

  def quote_params
    params.permit(:hotel_id, :room_type_id, :check_in, :check_out, :adults, :children, :room_count, :guest_name, :guest_email, :guest_phone)
  end

  def public_quote_url(token)
    Rails.application.routes.url_helpers.quote_url(token, host: request.base_url)
  end
end
