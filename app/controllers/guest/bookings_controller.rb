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
      scope = @status_filter == "confirmed" ? scope.where(status: %w[confirmed no_show_detected]) : scope.where(status: @status_filter)
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
    pdf_bytes = Reports::Bookings::GenerateConfirmation.new(@booking).generate
    send_data pdf_bytes,
      filename: "wastays-receipt-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def invoice
    @booking = current_guest.bookings.find(params[:id])
    pdf_bytes = ::Reports::Bookings::GeneratePrimaryGuestInvoice.new(booking: @booking).generate
    send_data pdf_bytes,
      filename: "wastays-invoice-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ::Reports::Bookings::GenerateFolioRecords::UnavailableError
    redirect_to guest_bookings_path, alert: "No finalized guest invoice is available for this booking."
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  # The guest is signed in, so the group is reached through a room they own rather than
  # through a code they were sent.
  def voucher_pack
    booking = current_guest.bookings.includes(:group_booking).find(params[:id])
    group_booking = booking.group_booking
    return redirect_to guest_booking_path(booking), alert: "This booking is not part of a group." if group_booking.blank?

    send_data Reports::Bookings::GenerateVoucherPack.new(group_booking).generate,
      filename: "wastays-vouchers-#{group_booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue Reports::Bookings::GenerateVoucherPack::EmptyGroupError
    redirect_to guest_booking_path(booking), alert: "This group has no rooms to print."
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  # A room in a group reports the group's position, because that is the position anyone
  # settles.
  def summary
    booking = current_guest.bookings.includes(:group_booking).find(params[:id])
    subject = booking.group_booking || booking
    pdf_bytes = if subject.is_a?(GroupBooking)
      Reports::Bookings::GenerateBookingSummary.new(group_booking: subject).generate
    else
      Reports::Bookings::GenerateBookingSummary.new(booking: subject).generate
    end

    send_data pdf_bytes,
      filename: "wastays-booking-summary-#{subject.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def toggle_dnd
    @booking = current_guest.bookings.find(params[:id])
    result = Guest::ToggleDndService.new(booking: @booking).call

    if result.success?
      redirect_to guest_booking_path(@booking), notice: result.message
    else
      redirect_to guest_booking_path(@booking), alert: result.error
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end
end
