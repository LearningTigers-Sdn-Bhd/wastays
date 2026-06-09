# frozen_string_literal: true

class HotelPortal::Bookings::CheckoutsController < HotelPortal::BaseController
  include BookingAuditable

  before_action :authorize_view_bookings!, only: [ :show ]
  before_action :authorize_manage_bookings!, only: [ :create, :process_late_checkout ]

  def show
    @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions).find(params[:id])
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    render "hotel_portal/bookings/checkout"
  end

  def create
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
        set_audit_logs(@booking)
        flash.now[:alert] = result.error
        render "hotel_portal/bookings/show", status: :unprocessable_content
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

  private

  def transition_timestamp(attribute)
    params[attribute].presence || booking_params[attribute].presence
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :checked_in_at, :checked_out_at
    )
  end

  def early_departure_checkout?(timestamp)
    current_hotel.business_date_for(timestamp.presence || Time.current).to_date < @booking.check_out.to_date
  end

  def transition_status(status, timestamp, success_notice)
    options = {}
    if params[:override_night_audit] == "1"
      options[:override_night_audit] = true
      options[:reason] = params[:retroactive_reason]
    end

    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: status,
      timestamp: timestamp,
      user: current_user,
      options: options
    ).call

    if result.success?
      redirect_to hotel_booking_path(current_hotel, @booking), notice: success_notice
    else
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      set_audit_logs(@booking)
      flash.now[:alert] = result.error
      render "hotel_portal/bookings/show", status: :unprocessable_content
    end
  end

  def check_out_from_sheet(timestamp)
    @booking = current_hotel.bookings.includes(booking_folio: :folio_transactions).find(params[:id])
    error = nil

    ActiveRecord::Base.transaction do
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
      format.html { render "hotel_portal/bookings/checkout", status: :unprocessable_content }
    end
  end

  def dispatch_checkout_side_effects
    Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)
    Notifications::Dispatcher.new(event: :booking_completed, booking: @booking).call
    SendInvoiceEmailJob.perform_later(@booking.id)
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
