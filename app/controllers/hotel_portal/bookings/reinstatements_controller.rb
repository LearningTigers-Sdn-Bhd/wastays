# frozen_string_literal: true

class HotelPortal::Bookings::ReinstatementsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])

    result = Bookings::ReinstateReservation.new(
      booking: @booking,
      params: booking_params.slice(:booking_rooms_attributes),
      user: current_user,
      options: {
        override_night_audit: true,
        reason: params[:retroactive_reason]
      }
    ).call

    if result.success?
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking reinstated and checked in successfully."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to reinstate booking: #{result.error}"
    end
  end

  private

  def booking_params
    params.fetch(:booking, {}).permit(
      booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
    )
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
