class Guest::BookingsController < Guest::BaseController
  before_action :authenticate_guest!
  BOOKING_STATUSES = %w[pending confirmed checked_in completed cancelled].freeze

  def index
    @refund_policy = RefundPolicy.first
    @search_query = params[:q].to_s.strip
    @status_filter = params[:status].to_s.strip
    @status_options = BOOKING_STATUSES

    scope = current_guest.bookings.includes(:hotel, :refund_request)

    if @search_query.present?
      scope = scope.joins(:hotel).where(
        "hotels.name ILIKE :query OR bookings.confirmation_token ILIKE :query",
        query: "%#{@search_query}%"
      )
    end

    if @status_filter.present? && @status_options.include?(@status_filter)
      scope = @status_filter == "confirmed" ? scope.where(status: %w[confirmed review_no_show]) : scope.where(status: @status_filter)
    end

    @all_bookings = scope.order(check_in: :desc)
    @bookings = @all_bookings.page(params[:page]).per(25)
  end

  def show
    @refund_policy = RefundPolicy.first
    @booking = current_guest.bookings.find(params[:id])
    append_breadcrumb @booking.confirmation_token.upcase, guest_booking_path(@booking)

    assigned_rooms = @booking.booking_rooms.where.not(room_number: [ nil, "" ])
    @room_statuses = if assigned_rooms.any?
      RoomStatus.where(
        hotel_id: @booking.hotel_id,
        room_type_id: assigned_rooms.select(:room_type_id),
        room_number: assigned_rooms.select(:room_number)
      ).index_by { |rs| [ rs.room_type_id, rs.room_number ] }
    else
      {}
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def receipt
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = ReceiptPdfService.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-receipt-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def invoice
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = ::Reports::Bookings::GenerateInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    redirect_to guest_bookings_path, alert: "Invoice is only available after checkout."
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def toggle_dnd
    @booking = current_guest.bookings.find(params[:id])

    unless @booking.status == "checked_in"
      return redirect_to guest_booking_path(@booking), alert: "Cannot toggle Do Not Disturb if you are not currently checked in."
    end

    booking_rooms = @booking.booking_rooms.where.not(room_number: [ nil, "" ])
    if booking_rooms.empty?
      return redirect_to guest_booking_path(@booking), alert: "No room assigned to this booking."
    end

    any_toggled = false
    booking_rooms.each do |br|
      room_status = RoomStatus.find_or_create_by!(
        hotel: @booking.hotel,
        room_type: br.room_type,
        room_number: br.room_number
      )

      new_dnd_state = !room_status.active_dnd?

      result = Rooms::UpdateStatus.new(
        room_status: room_status,
        params: { dnd: new_dnd_state.to_s },
        user: nil
      ).call

      any_toggled ||= result.success?
    end

    if any_toggled
      redirect_to guest_booking_path(@booking), notice: "Do Not Disturb preference updated successfully."
    else
      redirect_to guest_booking_path(@booking), alert: "Unable to update Do Not Disturb preferences."
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end
end
