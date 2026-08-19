class Public::QuotesController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    result = BookingEngine::CreateQuote.new(
      quote_params.merge(
        corporate_rate: current_agent_account.present?,
        hotel_corporate_account_id: current_agent_account&.id
      )
    ).call

    if result.success?
      redirect_to quote_path(result.quote.token)
    else
      Rails.logger.error "QUOTE CREATION FAILED: #{result.message}"
      redirect_back fallback_location: root_path, alert: result.message
    end
  end

  def show
    quote = BookingQuote.find_by!(token: params[:id])

    if quote.expires_at < Time.current
      flash[:alert] = "Your quote has expired. Please search again."
      redirect_to root_path
    end

    @display_currency = display_currency_for_request(quote)
    @quote = Public::QuotePresenter.new(quote, view_context, @display_currency)
    @hotel = Public::HotelPresenter.new(quote.hotel, view_context)
    @quote_items = @quote.booking_quote_items
    @payment_gateway = @hotel.checkout_payment_gateway || "razorpay"
    @payment_ready = @hotel.effective_payment_setting(@payment_gateway).present?
  end

  def guest_lookup
    quote = BookingQuote.find_by!(token: params[:id])
    email = params[:email].to_s.strip.downcase

    if email.blank?
      return render json: { found: false, message: "Email is required." }, status: :unprocessable_content
    end

    guest = Guest.find_by(email: email)
    found = guest.present?

    payload = {
      found: found,
      guest_details: found ? guest_lookup_payload(guest) : {},
      quote_token: quote.token
    }

    render json: payload
  end

  private

  def quote_params
    params.permit(:hotel_id, :room_type_id, :check_in, :check_out, :adults, :children, :room_count, :display_currency, :rate_plan_id, :corporate_rate, :hotel_corporate_account_id, allocations: [ :room_type_id, :quantity ], child_ages: [])
  end

  def display_currency_for_request(quote)
    quote.display_currency.presence ||
      DisplayCurrencyResolver.new(params: params, cookies: cookies, request: request).call
  end

  def guest_lookup_payload(guest)
    {
      name: guest.name,
      email: guest.email,
      phone: guest.phone,
      government_id: guest.government_id,
      gender: guest.gender,
      city: guest.city,
      country: guest.country,
      document_type: guest.document_type,
      date_of_birth: guest.date_of_birth&.iso8601
    }.compact
  end
end
