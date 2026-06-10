# frozen_string_literal: true

class HotelPortal::Bookings::CancellationsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])

    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: "cancelled",
      user: current_user
    ).call

    if result.success?
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking cancelled successfully."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: result.error
    end
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
