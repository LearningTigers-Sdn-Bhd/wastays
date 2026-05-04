class Api::V1::BaseController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  before_action :authenticate_api_key!

  attr_reader :current_api_key

  private

  def authenticate_api_key!
    token = request.headers["Authorization"]&.split(" ")&.last
    @current_api_key = ApiKey.authenticate(token)

    unless @current_api_key
      render json: { error: "Unauthorized: Invalid or missing API key" }, status: :unauthorized
    end
  end

  def current_bearer
    current_api_key&.bearer
  end

  # Helper to scope hotels based on API key permissions
  def hotel_scope
    return Hotel.all if current_api_key.superadmin?

    case current_api_key.bearer_type
    when "Hotel"
      Hotel.where(id: current_api_key.bearer_id)
    when "Account"
      Hotel.where(account_id: current_api_key.bearer_id)
    else
      Hotel.none
    end
  end

  # Helper to scope bookings based on API key permissions
  def booking_scope
    return Booking.all if current_api_key.superadmin?

    case current_api_key.bearer_type
    when "Hotel"
      Booking.where(hotel_id: current_api_key.bearer_id)
    when "Account"
      Booking.joins(:hotel).where(hotels: { account_id: current_api_key.bearer_id })
    else
      Booking.none
    end
  end

  # Helper to check if a specific hotel is authorized for this key
  def authorize_hotel!(hotel_identifier)
    hotel = hotel_scope.where(slug: hotel_identifier.to_s).first || hotel_scope.find_by(id: hotel_identifier)
    unless hotel
      render json: { error: "Forbidden: You do not have access to this hotel" }, status: :forbidden
      return nil
    end

    hotel
  end
end
