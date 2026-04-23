# frozen_string_literal: true

class HotelPortal::BookingsController < HotelPortal::BaseController
  def index
    @all_bookings = current_hotel.bookings.recent_first
    @all_bookings = @all_bookings.search(params[:query]) if params[:query].present?
    @all_bookings = @all_bookings.where(status: params[:status]) if params[:status].present?

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
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { available_rooms: [] }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])

    available_rooms = Bookings::AvailableRoomNumbers.new(
      hotel: current_hotel,
      room_type: room_type,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      exclude_booking_id: params[:exclude_booking_id].presence
    ).call

    render json: { available_rooms: available_rooms }
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
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
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
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      @booking.errors.add(:base, result.errors.to_sentence)
      render :show, status: :unprocessable_content
    end
  end

  def check_in
    transition_status("checked_in", params[:checked_in_at], "Guest checked in successfully.")
    @booking = current_hotel.bookings.find(params[:id])

    # Allow updating room numbers during check-in
    if @booking.update(booking_params.merge(status: "checked_in", checked_in_at: resolve_event_time(:checked_in_at)))
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest has been checked in."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to check in guest."
    end
  end

  def check_out
    transition_status("completed", params[:checked_out_at], "Guest has been checked out.")
  end

  def cancel
    transition_status("cancelled", nil, "Booking cancelled successfully.")
  end

  private

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :status, :checked_in_at, :checked_out_at,
      booking_rooms_attributes: [ :id, :room_number ]
    )
  def transition_status(status, timestamp, success_notice)
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: status,
      timestamp: timestamp
    ).call
  end

    if result.success?
      redirect_to hotel_booking_path(current_hotel, @booking), notice: success_notice
    else
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_content
    end
  end

  def booking_params
    params.require(:booking).permit(:guest_name, :guest_email, :guest_phone, :status, :check_in, :check_out, :room_number, :room_type_id, :adults, :children, :total_amount)
  end
end
