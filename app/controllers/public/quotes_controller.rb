class Public::QuotesController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def create
    result = BookingEngine::CreateQuote.new(quote_params).call

    if result.success?
      redirect_to quote_path(result.quote.token)
    else
      redirect_back fallback_location: root_path, alert: result.message
    end
  end

  def show
    @quote = BookingQuote.find_by!(token: params[:id])

    if @quote.expires_at < Time.current
      flash[:alert] = "Your quote has expired. Please search again."
      redirect_to root_path
    end

    @hotel = @quote.hotel
    @quote_items = @quote.booking_quote_items
    @display_currency = display_currency_for_request
    @payment_gateway = @hotel.checkout_payment_gateway || "razorpay"
  end

  def guest_lookup
    quote = BookingQuote.find_by!(token: params[:id])
    email = params[:email].to_s.strip.downcase

    if email.blank?
      return render json: { found: false, message: "Email is required." }, status: :unprocessable_content
    end

    guest = Guest.find_by(email: email)
    found = guest.present?

    render json: {
      found: found,
      guest_details: found ? guest_lookup_payload(guest) : {},
      quote_token: quote.token
    }
  end

  private

  def quote_params
    params.permit(:hotel_id, :room_type_id, :check_in, :check_out, :adults, :children, :room_count)
  end

  def display_currency_for_request
    country_code = country_code_from_ip
    return "MYR" if country_code == "MY" || country_code.blank?

    "USD"
  end

  def country_code_from_ip
    ip = client_ip
    return "MY" if ip.blank? || private_ip?(ip)

    Rails.cache.fetch("ip-country:#{ip}", expires_in: 12.hours) do
      lookup_country_code(ip)
    end
  end

  def lookup_country_code(ip)
    require "net/http"
    require "json"

    uri = URI("https://ipapi.co/#{ip}/json/")
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data["country_code"]
  rescue StandardError
    nil
  end

  def client_ip
    request.headers["CF-Connecting-IP"] ||
      request.headers["X-Forwarded-For"]&.split(",")&.first&.strip ||
      request.remote_ip
  end

  def private_ip?(ip)
    require "ipaddr"
    addr = IPAddr.new(ip)
    addr.loopback? || addr.private?
  rescue IPAddr::InvalidAddressError
    false
  end

  def guest_lookup_payload(guest)
    {
      name: guest.name,
      email: guest.email,
      phone: guest.phone,
      government_id: guest.government_id,
      gender: guest.gender,
      country: guest.country,
      document_type: guest.document_type
    }.compact
  end
end
