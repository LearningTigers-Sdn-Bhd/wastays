# frozen_string_literal: true

class HotelPortal::BookingsController < HotelPortal::BaseController
  def index
    @all_bookings = current_hotel.bookings.recent_first
    if params[:query].present?
      @all_bookings = @all_bookings.where("guest_name ILIKE ? OR guest_email ILIKE ? OR guest_phone ILIKE ?", "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%")
    end
    @bookings = @all_bookings.page(params[:page]).per(25)
  end

  def new
    @booking = current_hotel.bookings.build(
      check_in: params[:check_in].presence || Date.current,
      check_out: params[:check_out].presence || Date.current + 1.day,
      adults: 2
    )
    @room_types = current_hotel.room_types.order(:name)
  end

  def availability
    begin
      if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
        return render json: { available_rooms: [] }
      end

      room_type = current_hotel.room_types.find_by(id: params[:room_type_id])
      return render json: { available_rooms: [] } unless room_type

      available_rooms = Bookings::AvailableRoomNumbers.new(
        hotel: current_hotel,
        room_type: room_type,
        check_in: Date.parse(params[:check_in]),
        check_out: Date.parse(params[:check_out]),
        exclude_booking_id: params[:exclude_booking_id].presence
      ).call

      render json: { available_rooms: available_rooms }
    rescue => e
      Rails.logger.error "Availability check failed: #{e.message}"
      render json: { available_rooms: [] }
    end
  end

  def create
    result = Bookings::CreateManualBooking.new(
      hotel: current_hotel,
      params: booking_params
    ).call

    if result.success?
      redirect_to hotel_booking_path(current_hotel, result.booking), notice: "Booking created successfully."
    else
      @booking = current_hotel.bookings.build(booking_params.except(:room_type_id, :room_number))
      @room_types = current_hotel.room_types.order(:name)
      flash.now[:alert] = result.errors.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def show
    @booking = current_hotel.bookings.find(params[:id])
    setup_show_variables
  end

  def update
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::UpdateStayService.new(
      booking: @booking,
      params: booking_params
    ).call

    if result.success?
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking updated successfully."
    else
      setup_show_variables
      @booking.errors.add(:base, result.errors.to_sentence)
      render :show, status: :unprocessable_content
    end
  end

  def check_in
    @booking = current_hotel.bookings.find(params[:id])

    if @booking.update(status: "checked_in", checked_in_at: params[:checked_in_at])
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest checked in successfully."
    else
      setup_show_variables
      render :show, status: :unprocessable_content
    end
  end

  def check_out
    @booking = current_hotel.bookings.find(params[:id])

    if @booking.update(status: "completed", checked_out_at: params[:checked_out_at])
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest checked out successfully."
    else
      setup_show_variables
      render :show, status: :unprocessable_content
    end
  end

  def cancel
    @booking = current_hotel.bookings.find(params[:id])

    if @booking.update(status: "cancelled")
      Bookings::InventoryManager.new(@booking).release
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking cancelled successfully."
    else
      setup_show_variables
      render :show, status: :unprocessable_content
    end
  end

  private

  def setup_show_variables
    @room_types = current_hotel.room_types.order(:name)
    @booking_rooms = @booking.booking_rooms
    @pre_checkin = @booking.pre_checkin
    @housekeeping_requests = @booking.housekeeping_requests.where(archived_at: nil).or(
      @booking.housekeeping_requests.where(status: "cancelled")
    ).recent_first
    @pending_housekeeping_requests_count = @booking.housekeeping_requests.active.where(status: "pending").count
    @complaint_requests = @booking.complaint_requests.where(archived_at: nil).or(
      @booking.complaint_requests.where(status: "cancelled")
    ).recent_first
    @pending_complaint_requests_count = @booking.complaint_requests.active.where(status: "pending").count
    @pending_requests_count = @pending_housekeeping_requests_count + @pending_complaint_requests_count
  end

  def booking_params
    params.require(:booking).permit(:guest_name, :guest_email, :guest_phone, :status, :check_in, :check_out, :room_number, :room_type_id, :adults, :children, :total_amount)
  end
end
