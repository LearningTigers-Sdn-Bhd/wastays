class Guest::BookingsController < Guest::BaseController
  include ConciergeStaySession

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
        "hotels.name ILIKE :query OR bookings.confirmation_token ILIKE :query OR bookings.reservation_reference ILIKE :query",
        query: "%#{@search_query}%"
      )
    end

    if @status_filter.present? && @status_options.include?(@status_filter)
      scope = scope.where(status: Guest::StatusBadges::BOOKING_GROUPS.fetch(@status_filter))
    end

    @all_bookings = scope.order(check_in: :desc, id: :desc)
    @pagy, @bookings = pagy(:offset, @all_bookings, limit: 25)
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
    send_guest_document(:receipt)
  end

  def invoice
    send_guest_document(:invoice, failure_path: guest_bookings_path)
  end

  # The guest is signed in, so the group is reached through a room they own rather than
  # through a code they were sent.
  def voucher_pack
    send_guest_document(:voucher_pack)
  end

  def summary
    send_guest_document(:summary)
  end

  # Opens in a new tab. A stay with a stay page goes straight into it, signed
  # in; any other stay goes to the property's public concierge.
  def concierge
    booking = current_guest.bookings.includes(:hotel).find(params[:id])
    hotel = booking.hotel
    result = Guest::OpenConcierge.new(booking:).call

    unless result.success?
      return redirect_to concierge_home_path(hotel_code: hotel.unique_id, public_id: hotel.public_id)
    end

    start_concierge_stay_session(result.stay_access, expires_at: result.expires_at)
    redirect_to concierge_stay_path(hotel.unique_id, hotel.public_id, result.stay_access.stay_access_id)
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

  def e_invoice
    @booking = current_guest.bookings.find(params[:id])
    submission = EInvoice::SelectGuestSubmission.new(
      booking: @booking,
      submission_id: params[:submission_id]
    ).call
    raise ActiveRecord::RecordNotFound unless submission

    send_guest_document(:e_invoice, booking: @booking, submission: submission)
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def request_e_invoice
    @booking = current_guest.bookings.find(params[:id])
    result = EInvoice::RequestForGuest.new(booking: @booking).call

    unless result.success?
      status = result.already_queued ? :accepted : :unprocessable_content
      return respond_to_e_invoice_request_error(result.error, status)
    end

    respond_to do |format|
      format.html do
        redirect_to guest_booking_path(@booking),
          notice: "Your e-invoice request has been submitted. You will receive it shortly."
      end
      format.json do
        render json: {
          status: "queued",
          message: "Your e-invoice request has been submitted. We are preparing it now."
        }, status: :accepted
      end
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def status_e_invoice
    @booking = current_guest.bookings.find(params[:id])
    render json: EInvoice::GuestStatusPayload.new(
      booking: @booking,
      download_url: e_invoice_guest_booking_path(@booking)
    ).call
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  private

  # Every document goes out through Bookings::GuestDocument, so the bytes, the
  # filename, and the reason one is unavailable live in one place.
  # failure_path keeps each action's own landing page. The invoice has always
  # sent an unavailable document back to the list, and the group documents have
  # always stayed on the booking.
  def send_guest_document(kind, booking: nil, submission: nil, failure_path: nil)
    booking ||= current_guest.bookings.includes(:group_booking).find(params[:id])
    result = Bookings::GuestDocument.new(booking: booking, kind: kind, submission: submission).call

    unless result.success?
      return redirect_to(failure_path || guest_booking_path(booking), alert: result.error)
    end

    send_data result.bytes, filename: result.filename, type: "application/pdf", disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end

  def respond_to_e_invoice_request_error(message, status = :unprocessable_content)
    respond_to do |format|
      format.html { redirect_to guest_booking_path(@booking), alert: message }
      format.json { render json: { status: "failed", message: message }, status: status }
    end
  end
end
