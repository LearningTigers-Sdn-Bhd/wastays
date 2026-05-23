# frozen_string_literal: true

require "ostruct"

class HotelPortal::BookingsController < HotelPortal::BaseController
  before_action :authorize_view_bookings!, only: %i[index show availability rate_options stay_price folio_invoice]
  before_action :authorize_manage_bookings!, only: %i[new create update checkout check_in check_out cancel reinstate add_guest remove_guest process_late_checkout]

  def index
    @all_bookings = current_hotel.bookings.recent_first.includes(:booking_folio)
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
    unless turbo_frame_request?
      redirect_to hotel_bookings_path(current_hotel)
      return
    end

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
    rate_plan = rate_plan_for(room_type, params[:rate_plan_id])

    snapshot = Bookings::BuildFinancialSnapshot.new(
      hotel: current_hotel,
      room_type: room_type,
      rate_plan: rate_plan,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      guest_country: params[:guest_country].presence || current_hotel.country,
      corporate_rate: params[:corporate_rate] == "true"
    ).call
    total = snapshot.room_total + snapshot.tax_total

    render json: { total_amount: total }
  rescue ArgumentError => e
    render json: { error: e.message, total_amount: 0 }, status: :unprocessable_content
  end

  def rate_options
    if params[:check_in].blank? || params[:check_out].blank? || params[:room_type_id].blank?
      return render json: { rate_options: [] }
    end

    room_type = current_hotel.room_types.find(params[:room_type_id])
    options = Bookings::RateOptions.new(
      room_type: room_type,
      check_in: Date.parse(params[:check_in]),
      check_out: Date.parse(params[:check_out]),
      apply_stop_sell: params[:apply_stop_sell_restriction],
      apply_arrival_departure: params[:apply_arrival_departure_restrictions],
      apply_stay_length: params[:apply_stay_length_restrictions]
    ).call

    render json: { rate_options: options }
  end

  def create
    result = Bookings::CreateManualBooking.new(
      hotel: current_hotel,
      params: booking_params,
      user: current_user
    ).call

    if result.success?
      release_room_locks(result.booking)

      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = "Booking created successfully."
          render turbo_stream: turbo_stream_redirect_to(hotel_booking_path(current_hotel, result.booking))
        end
        format.html { redirect_to hotel_booking_path(current_hotel, result.booking), notice: "Booking created successfully." }
      end
    else
      Rails.logger.error "ManualBooking Creation Failed: #{result.errors.join(", ")}"
      @booking = current_hotel.bookings.build(booking_params.except(*manual_booking_form_only_param_keys))
      result.errors.each { |error| @booking.errors.add(:base, error) }
      @room_types = current_hotel.room_types.order(:name)
      flash.now[:alert] = result.errors.to_sentence

      respond_to do |format|
        format.turbo_stream { render :new, formats: [ :html ], layout: false, status: :unprocessable_content }
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def show
    @booking = current_hotel.bookings.includes(:booking_folio).find(params[:id])
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    set_audit_logs
  end

  def folio
    @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions).find(params[:id])
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
  end

  def checkout
    @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions).find(params[:id])
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
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
    timestamp = transition_timestamp(:checked_in_at)
    transition_status("checked_in", timestamp, "Guest checked in successfully.")
  end

  def check_out
    timestamp = transition_timestamp(:checked_out_at)
    return check_out_from_sheet(timestamp) if params[:checkout_sheet] == "1"

    @booking = current_hotel.bookings.find(params[:id])

    if early_departure_checkout?(timestamp)
      options = { timestamp: timestamp }
      if params[:override_night_audit] == "1"
        options[:override_night_audit] = true
        options[:correction_reason] = params[:retroactive_reason]
        options[:correction_note] = "Early departure override"
      end

      result = Bookings::ProcessEarlyDeparture.call(
        booking: @booking,
        user: current_user,
        params: params.permit(:apply_charge, :charge_amount),
        options: options
      )

      if result.success?
        redirect_to hotel_booking_path(current_hotel, @booking, checkout_success: true), notice: "Guest has been checked out with early departure."
      else
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        set_audit_logs
        flash.now[:alert] = result.error
        render :show, status: :unprocessable_content
      end
    else
      transition_status("completed", timestamp, "Guest has been checked out.")
    end
  end

  def process_late_checkout
    @booking = current_hotel.bookings.find(params[:id])

    if params[:check_out].present?
      unless @booking.update(check_out: params[:check_out])
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to update checkout period: #{@booking.errors.full_messages.to_sentence}"
      end
    end

    should_charge = params[:charge_type] != "none" && params[:amount].to_f > 0

    if should_charge
      result = Folios::PostCategoryCharge.call(
        folio: @booking.booking_folio,
        user: current_user,
        category: "late_checkout_charge",
        amount: params[:amount],
        description: "Late Checkout Charge"
      )

      unless result.success?
        return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to apply late checkout charge: #{result.error}"
      end
    end

    Bookings::TransitionStatus.new(
      booking: @booking,
      status: "checked_in",
      user: current_user,
      options: { event: "resolve_late_checkout" }
    ).call

    notice = should_charge ? "Late checkout charge applied." : "Late checkout resolved without charge."
    redirect_to hotel_booking_path(current_hotel, @booking), notice: notice
  end

  def cancel
    transition_status("cancelled", nil, "Booking cancelled successfully.")
  end

  def reinstate
    @booking = current_hotel.bookings.find(params[:id])

    result = Bookings::ReinstateReservation.new(
      booking: @booking,
      params: booking_params.slice(:booking_rooms_attributes),
      user: current_user,
      options: {
        override_night_audit: true,
        reason: params[:retroactive_reason]
      }
    ).call

    if result.success?
      redirect_to hotel_booking_path(current_hotel, @booking), notice: "Booking reinstated and checked in successfully."
    else
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Failed to reinstate booking: #{result.error}"
    end
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

  def complete_housekeeping_request
    @booking = current_hotel.bookings.find(params[:id])
    updater = ::HotelPortal::Requests::StatusUpdater.new(
      hotel: current_hotel,
      kind: "housekeeping",
      request_id: params[:housekeeping_request_id],
      status: "completed"
    )

    if updater.call
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), notice: "Housekeeping request completed."
    else
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), alert: "Failed to update request."
    end
  end

  def resolve_complaint_request
    @booking = current_hotel.bookings.find(params[:id])
    updater = ::HotelPortal::Requests::StatusUpdater.new(
      hotel: current_hotel,
      kind: "complaint",
      request_id: params[:complaint_request_id],
      status: "resolved"
    )

    if updater.call
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), notice: "Complaint resolved."
    else
      redirect_to hotel_booking_path(current_hotel, @booking, tab: "requests"), alert: "Failed to update request."
    end
  end

  def folio_invoice
    @booking = current_hotel.bookings
      .includes(booking_folio: :folio_transactions, booking_rooms: :room_type)
      .find(params[:id])

    folio = @booking.booking_folio
    unless folio&.status == "closed"
      redirect_to hotel_booking_path(current_hotel, @booking),
        alert: "Folio invoice is only available for checked-out bookings with a closed folio."
      return
    end

    pdf_bytes = FolioInvoicePdfService.new(@booking).generate
    filename  = "folio-invoice-#{@booking.formatted_invoice_number || @booking.confirmation_token}.pdf"

    respond_to do |format|
      format.pdf do
        send_data pdf_bytes, filename: filename, type: "application/pdf", disposition: "inline"
      end
      format.html do
        send_data pdf_bytes, filename: filename, type: "application/pdf", disposition: "attachment"
      end
    end
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
    @booking.assign_attributes(booking_params.except(:checked_in_at, :checked_out_at)) if params[:booking].present?

    options = {}
    if params[:override_night_audit] == "1"
      options[:override_night_audit] = true
      options[:reason] = params[:retroactive_reason]
    end
    options[:security_deposit] = security_deposit_options if collect_security_deposit?

    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: status,
      timestamp: timestamp,
      user: current_user,
      options: options
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
      set_audit_logs

      respond_to do |format|
        format.turbo_stream do
          if reservation_board_request?
            # Append an alert toast to the board instead of rendering show
            render turbo_stream: turbo_stream.append("reservation_board", partial: "shared/toast", locals: { key: "alert", value: result.error })
          else
            flash.now[:alert] = result.error
            render :show, formats: [ :html ], status: :unprocessable_content
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
      :guest_name, :guest_email, :guest_phone, :checked_in_at, :checked_out_at,
      :guest_country, :guest_gender, :guest_document_type, :guest_government_id, :guest_update_intent,
      :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
      :record_payment, :payment_method, :payment_amount, :payment_reference,
      :id_front, :id_back, :source, :internal_notes, :manual_rate_override, :existing_guest_id,
      :rate_plan_id, :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
      booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
    )
  end

  def collect_security_deposit?
    ActiveModel::Type::Boolean.new.cast(params[:collect_security_deposit]) && params[:security_deposit_amount].to_d.positive?
  end

  def security_deposit_options
    {
      amount: params[:security_deposit_amount],
      payment_method: params[:security_deposit_payment_method],
      external_reference: params[:security_deposit_reference]
    }
  end

  def rate_plan_for(room_type, rate_plan_id)
    return if rate_plan_id.blank?

    room_type.rate_plans.find_by(id: rate_plan_id)
  end

  def manual_booking_form_only_param_keys
    %i[
      room_type_id room_number record_payment payment_method payment_amount payment_reference
      existing_guest_id guest_update_intent rate_plan_id
      apply_stop_sell_restriction apply_arrival_departure_restrictions apply_stay_length_restrictions
    ]
  end

  def turbo_stream_redirect_to(path)
    %(<turbo-stream action="redirect" url="#{ERB::Util.html_escape(path)}"></turbo-stream>).html_safe
  end

  def transition_timestamp(attribute)
    params[attribute].presence || booking_params[attribute].presence
  end

  def check_out_from_sheet(timestamp)
    @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions).find(params[:id])
    error = nil

    ActiveRecord::Base.transaction do
      # 1. Handle Early Departure Penalty if applicable
      if early_departure_checkout?(timestamp)
        options = { timestamp: timestamp }
        if params[:override_night_audit] == "1"
          options[:override_night_audit] = true
          options[:correction_reason] = params[:retroactive_reason]
          options[:correction_note] = "Early departure override"
        end

        res = Bookings::ProcessEarlyDeparture.call(
          booking: @booking,
          user: current_user,
          params: params.permit(:apply_charge, :charge_amount),
          options: options.merge(defer_checkout: true, defer_side_effects: true)
        )

        if res.success?
          @booking.reload
        else
          error = res.error
          raise ActiveRecord::Rollback
        end

        @booking.association(:booking_folio).reset
      end

      settlement_result = post_checkout_settlement_payment
      if settlement_result&.success? == false
        error = settlement_result.error
        raise ActiveRecord::Rollback
      end

      result = Bookings::TransitionStatus.new(
        booking: @booking,
        status: "completed",
        timestamp: timestamp,
        user: current_user,
        options: { defer_side_effects: true }
      ).call

      unless result.success?
        error = result.error
        raise ActiveRecord::Rollback
      end
    end

    if error.present?
      return render_checkout_sheet_error(error)
    end

    dispatch_checkout_side_effects
    redirect_to hotel_booking_path(current_hotel, @booking, checkout_success: true), notice: "Guest has been checked out."
  end

  def post_checkout_settlement_payment
    return if checkout_payment_amount.blank?
    return OpenStruct.new(success?: true) if checkout_payment_amount.zero?

    return OpenStruct.new(success?: false, error: "Booking has no folio.") unless @booking.booking_folio
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("post_folio_payments", hotel: current_hotel)
    return OpenStruct.new(success?: false, error: "Checkout payment method is not supported.") unless checkout_payment_method == "cash"

    balance = @booking.booking_folio.outstanding_balance.to_d
    return OpenStruct.new(success?: false, error: "Checkout payment can only be posted for a positive outstanding balance.") unless balance.positive?
    return OpenStruct.new(success?: false, error: "Checkout payment cannot exceed the outstanding balance.") if checkout_payment_amount > balance

    Folios::PostStaffTransaction.call(
      folio: @booking.booking_folio,
      user: current_user,
      transaction_type: "payment",
      category: "cash",
      amount: checkout_payment_amount,
      description: checkout_payment_description,
      posting_date: current_hotel.business_date_for(transition_timestamp(:checked_out_at).presence || Time.current)
    )
  end

  def early_departure_checkout?(timestamp)
    current_hotel.business_date_for(timestamp.presence || Time.current).to_date < @booking.check_out.to_date
  end

  def checkout_payment_amount
    @checkout_payment_amount ||= params[:checkout_payment_amount].to_d
  end

  def checkout_payment_description
    reference = params[:checkout_payment_reference].presence
    [ "Checkout payment via Cash", reference && "Receipt #{reference}" ].compact.join(" - ")
  end

  def checkout_payment_method
    params[:checkout_payment_method].presence || "cash"
  end

  def render_checkout_sheet_error(error)
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    @checkout_error = error
    flash.now[:alert] = error

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "offcanvas_drawer",
          partial: "hotel_portal/bookings/checkout_sheet",
          locals: { booking: @booking, presenter: @presenter, hotel: current_hotel, checkout_error: error }
        ), status: :unprocessable_content
      end
      format.html { render :checkout, status: :unprocessable_content }
    end
  end

  def render_checkout_invoice_step
    @booking.reload
    @booking.association(:booking_folio).reset
    @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions).find(@booking.id)
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "offcanvas_drawer",
          partial: "hotel_portal/bookings/checkout_invoice_step",
          locals: { booking: @booking, presenter: @presenter, hotel: current_hotel }
        )
      end
      format.html { redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest has been checked out." }
    end
  end

  def dispatch_checkout_side_effects
    Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)
    Notifications::Dispatcher.new(event: :booking_completed, booking: @booking).call
    SendInvoiceEmailJob.perform_later(@booking.id)
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
