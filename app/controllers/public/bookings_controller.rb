class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @booking = Booking.find_by!(confirmation_token: params[:id])
    @hotel = @booking.hotel
    @booking_rooms = @booking.booking_rooms
  end
end
