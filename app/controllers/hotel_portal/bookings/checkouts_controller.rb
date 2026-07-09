# frozen_string_literal: true

class HotelPortal::Bookings::CheckoutsController < HotelPortal::BaseController
  include BookingAuditable
  include OffcanvasTransactionCompletion
  include GroupLifecycleTargeting

  before_action :authorize_manage_bookings!, only: [ :create, :process_late_checkout ]

  def create
    timestamp = transition_timestamp(:checked_out_at)
    return check_out_from_sheet(timestamp) if params[:checkout_sheet] == "1"

    @booking = current_hotel.bookings.find(params[:id])
    return render_checkout_sheet_error("Check-out date and time can't be blank.") if @booking.checkout_required? && timestamp.blank?

    if early_departure_checkout?(timestamp)
      options = { timestamp: timestamp }

      result = Bookings::ProcessEarlyDeparture.call(
        booking: @booking,
        user: current_user,
        params: params.permit(:apply_charge, :charge_amount),
        options: options
      )

      if result.success?
        respond_to do |format|
          format.turbo_stream do
            flash[:notice] = "Guest has been checked out with early departure."
            render_offcanvas_completion(checkout_success_path)
          end
          format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details", checkout_success: true), notice: "Guest has been checked out with early departure." }
        end
      else
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        set_audit_logs(@booking)

        respond_to do |format|
          format.turbo_stream do
            if booking_timeline_board_request?
              render turbo_stream: turbo_stream.append("booking_timeline_board", partial: "shared/toast", locals: { key: "alert", value: result.error })
            else
              flash[:alert] = result.error
              render_offcanvas_completion(booking_details_path)
            end
          end
          format.html do
            redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: result.error, status: :see_other
          end
        end
      end
    else
      transition_status("completed", timestamp, "Guest has been checked out.")
    end
  end

  def process_late_checkout
    @booking = current_hotel.bookings.find(params[:id])
    return batch_process_late_checkout if selected_lifecycle_batch?(@booking)

    result = Bookings::ProcessLateCheckout.call(
      booking: @booking,
      user: current_user,
      params: late_checkout_params
    )

    return redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: result.error unless result.success?

    if result.rejected?
      return render_checkout_required_response("Late checkout rejected. Complete checkout to resolve the booking.")
    end

    notice = result.charged? ? "Late checkout charge applied." : "Late checkout resolved without charge."
    offcanvas_transaction_response(
      destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
      notice: notice
    )
  end

  private

  def batch_process_late_checkout
    bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :late_checkout)
    results = []

    ActiveRecord::Base.transaction do
      bookings.each do |booking|
        result = Bookings::ProcessLateCheckout.call(booking: booking, user: current_user, params: late_checkout_params)
        raise BatchTargetError, result.error unless result.success?

        results << result
      end
    end

    past_tense_action = results.first.rejected? ? "late checkout rejected" : "resolved for late checkout"
    offcanvas_transaction_response(
      destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
      notice: batch_lifecycle_notice(bookings, past_tense_action)
    )
  rescue BatchTargetError => e
    redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: e.message, status: :see_other
  end

  def transition_timestamp(attribute)
    params[attribute].presence || booking_params[attribute].presence
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :checked_in_at, :checked_out_at
    )
  end

  def late_checkout_params
    params.permit(:charge_type, :amount, :check_out, :charge_calculation, :custom_type, :custom_value)
  end

  def early_departure_checkout?(timestamp)
    current_hotel.business_date_for(timestamp.presence || Time.current).to_date < @booking.check_out.to_date
  end

  def transition_status(status, timestamp, success_notice)
    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: status,
      timestamp: timestamp,
      user: current_user,
      options: {}
    ).call

    if result.success?
      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = success_notice
          render_offcanvas_completion(checkout_success_path)
        end
        format.html { redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), notice: success_notice }
      end
    else
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      set_audit_logs(@booking)

      respond_to do |format|
        format.turbo_stream do
          if booking_timeline_board_request?
            render turbo_stream: turbo_stream.append("booking_timeline_board", partial: "shared/toast", locals: { key: "alert", value: result.error })
          else
            flash[:alert] = result.error
            render_offcanvas_completion(booking_details_path)
          end
        end
        format.html do
          redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: result.error, status: :see_other
        end
      end
    end
  end

  def booking_timeline_board_request?
    params[:source] == "booking_timeline_board" || request.referer&.include?("bookings/board")
  end

  def check_out_from_sheet(timestamp)
    @booking = checkout_booking_scope.find(params[:id])
    error = nil
    completed_bookings = []
    targets = checkout_targets

    ActiveRecord::Base.transaction do
      targets.each do |booking|
        result = process_checkout_for_booking(booking, timestamp)
        unless result.success?
          error = targets.one? ? result.error : "#{checkout_booking_label(booking)}: #{result.error}"
          raise ActiveRecord::Rollback
        end

        completed_bookings << booking
      end
    end

    if error.present?
      return render_checkout_sheet_error(error)
    end

    completed_bookings.each { |booking| dispatch_checkout_side_effects(booking) }
    notice = completed_bookings.one? ? "Guest has been checked out." : "#{completed_bookings.size} bookings checked out."
    offcanvas_transaction_response(destination: checkout_success_path, notice: notice)
  rescue BatchTargetError => e
    render_checkout_sheet_error(e.message)
  end

  def process_checkout_for_booking(booking, timestamp)
    Checkouts::ProcessBookingCheckout.call(
      booking: booking,
      hotel: current_hotel,
      user: current_user,
      timestamp: timestamp,
      folio_action_params: checkout_folio_action_params(booking),
      posting_date: current_hotel.current_business_date,
      early_departure_params: early_departure_params_for(booking),
      checkout_options: checkout_blocker_resolution_options(booking),
      security_deposit_options: security_deposit_release_options
    )
  end

  def early_departure_params_for(booking)
    scoped = params.dig(:early_departures, booking.id.to_s) || params.dig(:early_departures, booking.id)
    return params.permit(:apply_charge, :charge_amount).to_h.symbolize_keys if scoped.blank?

    permitted = scoped.respond_to?(:to_unsafe_h) ? scoped.to_unsafe_h : scoped.to_h
    { apply_charge: permitted["apply_charge"], charge_amount: permitted["charge_amount"] }
  end

  def checkout_targets
    return [ @booking ] unless selected_lifecycle_batch?(@booking)

    selected_lifecycle_bookings(fallback_booking: @booking, action: :checkout)
  end

  def checkout_blocker_resolution_options(booking = @booking)
    return {} unless booking&.checkout_required?
    return {} unless current_hotel.current_business_date_record&.audit_blocked?

    audit = current_hotel.night_audits.where(business_date: current_hotel.current_business_date).order(created_at: :desc).first
    return {} unless audit

    {
      posting_source: "audit_blocker_resolution",
      correction_reason: "Resolve checkout-required night audit blocker",
      blocker_resolution: {
        night_audit_id: audit.id,
        blocker_type: "due_out_not_checked_out",
        booking_id: booking.id
      }
    }
  end

  def checkout_folio_action_params(booking = @booking)
    scoped = params.dig(:checkout_bookings, booking.id.to_s, :folios) || params.dig(:checkout_bookings, booking.id, :folios)
    raw_params = scoped.presence || params[:checkout_folios]
    return default_checkout_folio_action_params(booking) if raw_params.blank?

    permitted = raw_params.respond_to?(:to_unsafe_h) ? raw_params.to_unsafe_h : raw_params.to_h
    permitted.transform_values do |value|
      value.to_h.slice("action", "amount", "payment_method", "payment_reference", "reason")
    end
  end

  def default_checkout_folio_action_params(booking)
    HotelPortal::Checkouts::SheetPresenter.new(booking: booking, hotel: current_hotel, user: current_user).folio_rows.each_with_object({}) do |row, actions|
      actions[row.folio.id.to_s] = {
        "action" => row.default_action,
        "amount" => format('%.2f', row.balance.to_d)
      }
    end
  end

  def security_deposit_release_options
    return {} unless params[:release_security_deposit] == "1"

    {
      security_deposit_release: {
        method: params[:security_deposit_release_method].to_s.presence || "cash",
        reference: params[:security_deposit_release_reference].to_s.strip.presence
      }
    }
  end

  def checkout_booking_scope
    current_hotel.bookings.includes(
      :deposits,
        booking_folios: [ :folio_forecasted_charges, { folio_transactions: :user }, { hotel_corporate_account: :corporate_account } ]
    )
  end

  def render_checkout_sheet_error(error)
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    @checkout_error = error
    flash.now[:alert] = error

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "offcanvas_drawer",
          partial: "hotel_portal/bookings/transactions/check_out/partials/sheet",
          locals: {
            booking: @booking,
            presenter: @presenter,
            hotel: current_hotel,
            checkout_error: error,
            checkout_source: params[:source],
            transaction_return_to: offcanvas_return_to(fallback: nil)
          }
        ), status: :unprocessable_content
      end
      format.html { render "hotel_portal/bookings/transactions/check_out/offcanvas", status: :unprocessable_content }
    end
  end

  def render_checkout_required_response(notice)
    @booking.reload
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    flash.now[:notice] = notice

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "offcanvas_drawer",
          partial: "hotel_portal/bookings/transactions/check_out/partials/sheet",
          locals: {
            booking: @booking,
            presenter: @presenter,
            hotel: current_hotel,
            checkout_error: nil,
            checkout_source: params[:source],
            transaction_return_to: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"))
          }
        )
      end
      format.html { redirect_to hotel_booking_transaction_check_out_path(current_hotel, @booking), notice: notice, status: :see_other }
    end
  end

  def checkout_booking_label(booking)
    room = booking.booking_rooms.first
    room_type = room&.room_type&.name.presence || room&.room_type_snapshot.to_h["name"].presence || "Room type unavailable"
    room_number = room&.room_number.presence || "Unassigned room"
    number = booking.formatted_reservation_number.presence || booking.confirmation_token.presence || booking.id
    "Booking ##{number} / #{room_type} - #{room_number}"
  end

  def dispatch_checkout_side_effects(booking = @booking)
    Bookings::WebhookTriggerService.new(booking).trigger(:booking_completed)
    Notifications::Dispatcher.new(event: :booking_completed, booking: booking).call
    SendInvoiceEmailJob.perform_later(booking.id)
  end

  def checkout_success_path
    fallback = hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details", checkout_success: true)
    return offcanvas_return_to(fallback: fallback) if params[:return_to].present?
    return board_hotel_bookings_path(current_hotel) if booking_timeline_board_request?

    fallback
  end

  def booking_details_path
    hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
