# frozen_string_literal: true

class HotelPortal::Bookings::AvailabilitiesController < HotelPortal::BaseController
  before_action :authorize_view_bookings!

  def show
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { available_rooms: [] }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])

    service = Bookings::AvailableRoomNumbers.new(
      hotel: current_hotel,
      room_type: room_type,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      exclude_booking_id: params[:exclude_booking_id].presence
    )

    render json: { available_rooms: service.call, room_options: service.options }
  end

  private

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end
end
