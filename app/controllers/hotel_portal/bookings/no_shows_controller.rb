# frozen_string_literal: true

class HotelPortal::Bookings::NoShowsController < HotelPortal::BaseController
  include OffcanvasTransactionCompletion

  before_action :authorize_manage_bookings!

  def create
    booking = current_hotel.bookings.find(params[:id])
    result = Bookings::FinalizeNoShow.call(booking: booking, user: current_user)

    if result.success?
      offcanvas_transaction_response(
        destination: offcanvas_return_to(fallback: hotel_booking_path(current_hotel, booking)),
        notice: "Booking marked as no-show."
      )
    else
      redirect_to hotel_booking_path(current_hotel, booking), alert: result.error
    end
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
