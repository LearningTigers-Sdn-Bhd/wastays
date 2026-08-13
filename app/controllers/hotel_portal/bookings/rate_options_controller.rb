# frozen_string_literal: true

class HotelPortal::Bookings::RateOptionsController < HotelPortal::BaseController
  before_action :authorize_view_bookings!

  def show
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { rate_options: [] }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])
    options = Bookings::RateOptions.new(
      room_type: room_type,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      apply_stop_sell: params[:apply_stop_sell_restriction],
      apply_arrival_departure: params[:apply_arrival_departure_restrictions],
      apply_stay_length: params[:apply_stay_length_restrictions],
      audience: :staff,
      adults: params[:adults].presence,
      children: params[:children].presence
    ).call

    render json: { rate_options: options }
  end

  private

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end
end
