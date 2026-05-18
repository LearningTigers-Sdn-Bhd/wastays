# frozen_string_literal: true

class HotelPortal::BookingsController < HotelPortal::BaseController
  before_action :authorize_view_bookings!, only: %i[index show availability stay_price]
  before_action :authorize_manage_bookings!, only: %i[new create update check_in check_out cancel add_guest remove_guest]

  def index
    @all_bookings = current_hotel.bookings.recent_first
    @all_bookings = @all_bookings.search(params[:query]) if params[:query].present?
    @all_bookings = @all_bookings.where(status: params[:status]) if params[:status].present?

    @bookings = @all_bookings.page(params[:page]).per(25)
  end

  def sync
    authorize_manage_bookings!

    result = ChannelManagers::FetchBookingsService.new(hotel: current_hotel).call

    if result.success?
      redirect_to hotel_bookings_path(current_hotel), notice: result.message
    else
      redirect_to hotel_bookings_path(current_hotel), alert: result.message
    end
  end

  def new
    @booking = current_hotel.bookings.build(
      check_in: params[:check_in].presence || Date.current,
      check_out: params[:check_out].presence || Date.current + 1.day,
      adults: 2
    )

    if params[:room_type_id].present?
      room_type = current_hotel.room_types.find(params[:room_type_id])
      @booking.total_amount = Bookings::CalculateStayPrice.new(
        room_type: room_type,
        check_in: @booking.check_in,
        check_out: @booking.check_out
      ).call
    end

    @room_types = current_hotel.room_types.order(:name)
  end

  def availability
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { available_rooms: [] }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])

    service = Bookings::AvailableRoomNumbers.new(
      hotel: current_hotel,
      room_type: room_type,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      exclude_booking_id: params[:exclude_booking_id].presence
    )

    render json: { available_rooms: service.call, room_options: service.options }
  end

  def stay_price
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { total_amount: 0 }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])

    total = Bookings::CalculateStayPrice.new(
      room_type: room_type,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out])
    ).call

    render json: { total_amount: total }
  end

  def create
    result = Bookings::CreateManualBooking.new(
      hotel: current_hotel,
      params: booking_params,
      user: current_user
    ).call

    if result.success?
      release_room_locks(result.booking)
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
    set_audit_logs
  end

  def update
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::UpdateStayService.new(
      booking: @booking,
      params: booking_params,
      user: current_user,
      override: params[:override_room_status],
      override_reason: params[:override_room_status_reason]
    ).call

    if result.success?
      release_room_locks(@booking)
      respond_to do |format|
        format.html { redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking updated successfully." }
        format.json { render json: { success: true, booking: @booking } }
      end
    else
      respond_to do |format|
        format.html do
          @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
          set_audit_logs
          @booking.errors.add(:base, result.errors.to_sentence)
          render :show, status: :unprocessable_content
        end
        format.json { render json: { success: false, errors: result.errors }, status: :unprocessable_content }
      end
    end
  end

  def move
    @booking = current_hotel.bookings.find(params[:id])
    # For move, we only expect check_in, check_out, room_type_id, and room_number
    # We allow children and adults to stay the same if not provided
    move_params = params.permit(:check_in, :check_out, :room_type_id, :room_number)

    result = Bookings::UpdateStayService.new(
      booking: @booking,
      params: move_params,
      user: current_user
    ).call

    if result.success?
      render json: { success: true, booking: @booking.as_json(only: %i[id check_in check_out status]) }
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end

  def check_in
    transition_status("checked_in", params[:checked_in_at], "Guest checked in successfully.")
  end

  def check_out
    transition_status("completed", params[:checked_out_at], "Guest has been checked out.")
  end

  def cancel
    transition_status("cancelled", nil, "Booking cancelled successfully.")
  end

  def add_guest
    @booking = current_hotel.bookings.find(params[:id])
    guest = Guest.create!(
      name: params[:name].to_s.strip,
      phone: params[:phone].to_s.strip,
      email: params[:email].to_s.strip.presence,
      gender: params[:gender].to_s.strip.presence,
      government_id: params[:government_id].to_s.strip,
      document_type: params[:document_type].to_s.strip.presence || "ic",
      country: params[:country].presence || current_hotel.country.presence || "Malaysia"
    )
    @booking.booking_guests.create!(guest: guest, is_primary: false)
    redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to hotel_booking_path(current_hotel, @booking), alert: e.message
  end

  def remove_guest
    @booking = current_hotel.bookings.find(params[:id])
    bg = @booking.booking_guests.find_by!(id: params[:guest_id], is_primary: false)
    guest = bg.guest
    bg.destroy
    guest.destroy if guest.booking_guests.empty?
    redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest removed."
  end

  private

  def set_audit_logs
    # Fetch audit logs for this booking and its related entities
    base_query = BookingAuditLog.where(hotel: current_hotel)

    @audit_logs = base_query.where(auditable: @booking)

    if @booking.booking_quote_id.present?
      @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingQuote", auditable_id: @booking.booking_quote_id))
    end

    @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingRoom", auditable_id: @booking.booking_rooms.select(:id)))
                            .includes(:user, :auditable)
                            .order(created_at: :desc)
  end

  def release_room_locks(booking)
    # Release locks for all rooms assigned to this booking
    # Assuming the admin might have locked multiple rooms if they changed their mind
    # or if we just want to be safe and release all locks held by current user for this hotel
    # But more specifically, we should release the lock for the room they just assigned.
    room_number = booking.hotel_snapshot.is_a?(Hash) ? (booking.hotel_snapshot["room_number"] || booking.hotel_snapshot.dig("assignment", "room_number")) : nil
    RoomLock.where(hotel: current_hotel, user: current_user, room_number: room_number).destroy_all if room_number.present?
  end

  def transition_status(status, timestamp, success_notice)
    @booking = current_hotel.bookings.find(params[:id])

    # Apply nested attributes (like room assignment) if provided in the form
    @booking.assign_attributes(booking_params) if params[:booking].present?

    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: status,
      timestamp: timestamp,
      user: current_user
    ).call

    if result.success?
      release_room_locks(@booking) if status == "checked_in"

      respond_to do |format|
        format.turbo_stream do
          if reservation_board_request?
            render turbo_stream: turbo_stream.action(:reload, "reservation_board")
          else
            # Fallback for other pages that might use turbo streams but expect a redirect
            redirect_to hotel_booking_path(current_hotel, @booking), notice: success_notice, status: :see_other
          end
        end
        format.html { redirect_to hotel_booking_path(current_hotel, @booking), notice: success_notice }
      end
    else
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)

      respond_to do |format|
        format.turbo_stream do
          if reservation_board_request?
            # Append an alert toast to the board instead of rendering show
            render turbo_stream: turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "alert", value: result.error })
          else
            render :show, status: :unprocessable_content
          end
        end
        format.html do
          flash.now[:alert] = result.error
          render :show, status: :unprocessable_content
        end
      end
    end
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :status, :checked_in_at, :checked_out_at,
      :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
      booking_rooms_attributes: [ :id, :room_number ]
    )
  end

  def reservation_board_request?
    params[:source] == "reservation_board" || request.referer&.include?("reservation-board")
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
