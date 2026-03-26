class Hotel::BookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def index
    @bookings = current_hotel.bookings.order(created_at: :desc)
    
    # Simple filtering
    if params[:status].present?
      @bookings = @bookings.where(status: params[:status])
    end
    
    if params[:query].present?
      @bookings = @bookings.where("guest_name ILIKE :q OR confirmation_token ILIKE :q", q: "%#{params[:query]}%")
    end
  end

  def show
    @booking = current_hotel.bookings.find(params[:id])
    @booking_rooms = @booking.booking_rooms
  end

  def update
    @booking = current_hotel.bookings.find(params[:id])
    if @booking.update(booking_params)
      redirect_to hotel_booking_path(@booking), notice: "Booking updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def cancel
    @booking = current_hotel.bookings.find(params[:id])
    
    if @booking.update(status: 'cancelled')
      # Re-release inventory
      release_inventory(@booking)
      redirect_to hotel_booking_path(@booking), notice: "Booking has been cancelled."
    else
      redirect_to hotel_booking_path(@booking), alert: "Failed to cancel booking."
    end
  end

  private

  def booking_params
    params.require(:booking).permit(:guest_name, :guest_email, :guest_phone, :status)
  end

  def release_inventory(booking)
    # Similar logic to ReleaseExpiredHoldsJob but for confirmed bookings
    ActiveRecord::Base.transaction do
      booking.booking_rooms.each do |room|
        room_type = room.room_type
        quantity = room.quantity
        stay_dates = (booking.check_in...booking.check_out).to_a

        stay_dates.each do |date|
          inventory = room_type.room_inventories.find_by(date: date)
          inventory.update!(quantity: inventory.quantity + quantity) if inventory
        end
      end
    end
  end
end
