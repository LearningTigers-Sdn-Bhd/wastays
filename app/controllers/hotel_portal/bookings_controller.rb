class HotelPortal::BookingsController < HotelPortal::BaseController
  def index
    @bookings = current_hotel.bookings.order(created_at: :desc)

    # Simple filtering
    if params[:status].present?
      @bookings = @bookings.where(status: params[:status])
    end

    if params[:query].present?
      query = params[:query].strip
      @bookings = @bookings.where("guest_name ILIKE :q OR guest_email ILIKE :q OR guest_phone ILIKE :q OR confirmation_token ILIKE :q", q: "#{query}%")
    end
  end

  def show
    @booking = current_hotel.bookings.find(params[:id])
    @booking_rooms = @booking.booking_rooms
  end

  def update
    @booking = current_hotel.bookings.find(params[:id])
    if @booking.update(booking_params)
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking updated successfully."
    else
      render :show, status: :unprocessable_content
    end
  end

  def check_in
    @booking = current_hotel.bookings.find(params[:id])

    if @booking.update(status: "checked_in", checked_in_at: resolve_event_time(:checked_in_at))
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest has been checked in."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to check in guest."
    end
  end

  def check_out
    @booking = current_hotel.bookings.find(params[:id])

    if @booking.update(status: "completed", checked_out_at: resolve_event_time(:checked_out_at))
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest has been checked out."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to check out guest."
    end
  end

  def cancel
    @booking = current_hotel.bookings.find(params[:id])

    if @booking.update(status: "cancelled")
      # Re-release inventory
      release_inventory(@booking)
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking has been cancelled."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to cancel booking."
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

  def resolve_event_time(param_key)
    raw_value = params[param_key]
    return Time.current if raw_value.blank?

    Time.zone.parse(raw_value) || Time.current
  rescue ArgumentError, TypeError
    Time.current
  end
end
