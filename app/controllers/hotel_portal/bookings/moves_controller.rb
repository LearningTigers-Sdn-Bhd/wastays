# frozen_string_literal: true

class HotelPortal::Bookings::MovesController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def update
    @booking = current_hotel.bookings.find(params[:id])
    move_params = params.permit(:check_in, :check_out, :room_type_id, :room_number)

    result = Bookings::UpdateStayService.new(
      booking: @booking,
      params: move_params,
      user: current_user
    ).call

    if result.success?
      render json: { success: true, booking: @booking.as_json(only: %i[id check_in check_out status]) }
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
