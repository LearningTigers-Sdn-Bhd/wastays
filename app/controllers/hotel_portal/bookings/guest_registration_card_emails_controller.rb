# frozen_string_literal: true

class HotelPortal::Bookings::GuestRegistrationCardEmailsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!
  before_action :set_booking

  def create
    result = ::Bookings::SendGuestRegistrationCard.call(booking: @booking, user: current_user)

    if result.success?
      redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking),
        notice: "Guest registration card sent to #{result.recipient}."
    else
      redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), alert: result.error
    end
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
