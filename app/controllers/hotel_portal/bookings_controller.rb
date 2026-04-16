class HotelPortal::BookingsController < HotelPortal::BaseController
  def index
    @bookings = current_hotel.bookings.order(created_at: :desc)

    # Simple filtering
    if params[:status].present?
      @bookings = @bookings.where(status: params[:status])
    end

    if params[:query].present?
      query = params[:query].strip
      @bookings = @bookings.where("guest_name ILIKE :q OR guest_email ILIKE :q OR guest_phone ILIKE :q OR confirmation_token ILIKE :q", q: "%#{query}%")
    end
  end

  def show
    @booking = current_hotel.bookings.find(params[:id])
    @booking_rooms = @booking.booking_rooms
    @pre_checkin = @booking.pre_checkin
    @housekeeping_requests = @booking.housekeeping_requests.recent_first
    @pending_housekeeping_requests_count = @booking.housekeeping_requests.where(status: "pending").count
    @complaint_requests = @booking.complaint_requests.recent_first
    @pending_complaint_requests_count = @booking.complaint_requests.where(status: "pending").count
    @pending_requests_count = @pending_housekeeping_requests_count + @pending_complaint_requests_count
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

  def complete_housekeeping_request
    @booking = current_hotel.bookings.find(params[:id])
    request = @booking.housekeeping_requests.find(params[:housekeeping_request_id])

    request.add_internal_note(params[:internal_note], user_name: current_user.name)

    request.status = "completed"
    request.completed_at ||= Time.current

    if request.save
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), notice: "Housekeeping request marked as completed."
    else
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), alert: "Failed to update housekeeping request."
    end
  end

  def update_complaint_request
    @booking = current_hotel.bookings.find(params[:id])
    complaint_request = @booking.complaint_requests.find(params[:complaint_request_id])

    complaint_request.add_internal_note(params[:internal_note], user_name: current_user.name)

    requested_status = params[:status].presence || complaint_request.status || "in_progress"
    complaint_request.status = requested_status
    complaint_request.completed_at = nil unless complaint_request.resolved?

    if complaint_request.save
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), notice: "Complaint note saved."
    else
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), alert: "Failed to save complaint note."
    end
  end

  def resolve_complaint_request
    @booking = current_hotel.bookings.find(params[:id])
    complaint_request = @booking.complaint_requests.find(params[:complaint_request_id])

    complaint_request.resolved!

    if complaint_request.save
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), notice: "Complaint request marked as resolved."
    else
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), alert: "Failed to resolve complaint request."
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
