class Public::BookingsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  def show
    @booking = Booking.find_by!(confirmation_token: params[:id])
    @hotel = @booking.hotel
    @booking_rooms = @booking.booking_rooms
    @pre_checkin = @booking.pre_checkin || @booking.create_pre_checkin!(
      status: "pending",
      document_status: "pending",
      signature_status: "pending"
    )
  end
end
