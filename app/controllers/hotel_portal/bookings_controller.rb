class HotelPortal::BookingsController < HotelPortal::BaseController
  def index
    @all_bookings = current_hotel.bookings.order(created_at: :desc)

    # Simple filtering
    if params[:status].present?
      @all_bookings = @all_bookings.where(status: params[:status])
    end

    if params[:query].present?
      @all_bookings = @all_bookings.search(params[:query])
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

      check_in = Date.parse(params[:check_in])
      check_out = Date.parse(params[:check_out])
      
      room_type = current_hotel.room_types.find_by(id: params[:room_type_id])
      return render json: { available_rooms: [] } unless room_type

      # 1. Get all room numbers defined for this category
      all_rooms = room_type.room_numbers || []

      # 2. Find room numbers already occupied for these dates
      exclude_id = params[:exclude_booking_id].presence

      occupied = current_hotel.bookings.where(status: ["confirmed", "checked_in", "completed"])
      occupied = occupied.where.not(id: exclude_id) if exclude_id
      
      occupied_numbers = occupied.where("check_in < ? AND check_out > ?", check_out, check_in)
        .pluck(Arel.sql("hotel_snapshot->>'room_number'"))
        .compact.map(&:to_s).uniq

      # 3. Filter them out
      available_rooms = (all_rooms - occupied_numbers).reject(&:blank?)

      render json: { available_rooms: available_rooms }
    rescue => e
      Rails.logger.error "Availability check failed: #{e.message}"
      # Return empty instead of error to prevent 422 popup UI
      render json: { available_rooms: [] }
    end
  end

  def create
    @booking = current_hotel.bookings.build(booking_params.except(:room_type_id, :room_number))
    room_type = current_hotel.room_types.find(params[:booking][:room_type_id])
    room_number = params[:booking][:room_number]

    @booking.status = "confirmed"
    @booking.payment_status = "captured"
    @booking.hotel_snapshot = current_hotel.as_json.merge("room_number" => room_number)

    # Simple price calculation for manual bookings if not provided
    @booking.total_amount ||= room_type.base_price * (@booking.check_out - @booking.check_in).to_i

    ActiveRecord::Base.transaction do
      if @booking.save
        @booking.booking_rooms.create!(
          room_type: room_type,
          quantity: 1,
          subtotal: @booking.total_amount,
          room_type_snapshot: room_type.as_json
        )

        deduct_inventory(@booking)
        redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking created successfully."
      else
        @room_types = current_hotel.room_types.order(:name)
        render :new, status: :unprocessable_content
      end
    end
  rescue => e
    @room_types = current_hotel.room_types.order(:name)
    flash.now[:alert] = "Failed to create booking: #{e.message}"
    render :new, status: :unprocessable_content
  end

  def show
    @booking = current_hotel.bookings.find(params[:id])
    setup_show_variables
  end

  def update
    @booking = current_hotel.bookings.find(params[:id])

    update_params = booking_params
    room_number = update_params.delete(:room_number)
    room_type_id = update_params.delete(:room_type_id)

    ActiveRecord::Base.transaction do
      # 1. Handle Room Type / Inventory Change
      if room_type_id.present?
        new_room_type = current_hotel.room_types.find(room_type_id)
        current_room = @booking.booking_rooms.first

        if current_room && current_room.room_type_id != new_room_type.id
          # Release old inventory
          release_inventory(@booking)

          # Update or replace the booking room
          current_room.update!(
            room_type: new_room_type,
            room_type_snapshot: new_room_type.as_json,
            subtotal: new_room_type.base_price * (@booking.check_out - @booking.check_in).to_i
          )

          # Deduct new inventory (will be called after .update below to handle potential date changes too)
        end
      end

      # 2. Update room number in snapshot
      if room_number.present?
        @booking.hotel_snapshot ||= {}
        @booking.hotel_snapshot = @booking.hotel_snapshot.merge("room_number" => room_number)
      end

      # 3. Save main booking details
      old_dates = { check_in: @booking.check_in, check_out: @booking.check_out }

      if @booking.update(update_params)
        # 4. If dates changed or room type changed, sync inventory
        if old_dates[:check_in] != @booking.check_in || old_dates[:check_out] != @booking.check_out || room_type_id.present?
          # If only dates changed but not room type, we still need to release and re-deduct
          release_inventory_by_dates(@booking, old_dates[:check_in], old_dates[:check_out])
          deduct_inventory(@booking)
        end

        redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking updated successfully."
      else
        setup_show_variables
        render :show, status: :unprocessable_content
      end
    end
  rescue => e
    setup_show_variables
    @booking.errors.add(:base, "Update failed: #{e.message}")
    render :show, status: :unprocessable_content
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
    params.require(:booking).permit(:guest_name, :guest_email, :guest_phone, :status, :check_in, :check_out, :room_number, :room_type_id, :adults, :children, :total_amount)
  end

  def deduct_inventory(booking)
    ActiveRecord::Base.transaction do
      booking.booking_rooms.each do |room|
        room_type = room.room_type
        quantity = room.quantity
        stay_dates = (booking.check_in...booking.check_out).to_a

        stay_dates.each do |date|
          inventory = room_type.room_inventories.find_or_create_by!(date: date)
          inventory.update!(quantity: [ 0, inventory.quantity - quantity ].max)
        end
      end
    end
  end

  def release_inventory_by_dates(booking, start_date, end_date)
    ActiveRecord::Base.transaction do
      booking.booking_rooms.each do |room|
        room_type = room.room_type
        quantity = room.quantity
        stay_dates = (start_date...end_date).to_a

        stay_dates.each do |date|
          inventory = room_type.room_inventories.find_by(date: date)
          inventory.update!(quantity: inventory.quantity + quantity) if inventory
        end
      end
    end
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
