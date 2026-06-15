# frozen_string_literal: true

class HotelPortal::Bookings::CheckoutsController < HotelPortal::BaseController
  include BookingAuditable
  include OffcanvasTransactionCompletion

  before_action :authorize_view_bookings!, only: [ :show ]
  before_action :authorize_manage_bookings!, only: [ :create, :process_late_checkout ]

  def show
    @booking = current_hotel.bookings.includes(booking_folio: { folio_transactions: :user }).find(params[:id])
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    render "hotel_portal/bookings/transactions/check_out/offcanvas"
  end

  def create
    timestamp = transition_timestamp(:checked_out_at)
    return check_out_from_sheet(timestamp) if params[:checkout_sheet] == "1"

    @booking = current_hotel.bookings.find(params[:id])
    return render_checkout_sheet_error("Check-out date and time can't be blank.") if @booking.checkout_required? && timestamp.blank?

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
        respond_to do |format|
          format.turbo_stream do
            flash[:notice] = "Guest has been checked out with early departure."
            render_offcanvas_completion(checkout_success_path)
          end
          format.html { redirect_to hotel_booking_path(current_hotel, @booking, checkout_success: true), notice: "Guest has been checked out with early departure." }
        end
      else
        @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
        set_audit_logs(@booking)

        respond_to do |format|
          format.turbo_stream do
            if booking_timeline_board_request?
              render turbo_stream: turbo_stream.append("booking_timeline_board", partial: "shared/toast", locals: { key: "alert", value: result.error })
            else
              flash.now[:alert] = result.error
              render "hotel_portal/bookings/show", formats: [ :html ], status: :unprocessable_content
            end
          end
          format.html do
            flash.now[:alert] = result.error
            render "hotel_portal/bookings/show", status: :unprocessable_content
          end
        end
      end
    else
      transition_status("completed", timestamp, "Guest has been checked out.")
    end
  end

  def process_late_checkout
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::ProcessLateCheckout.call(
      booking: @booking,
      user: current_user,
      params: late_checkout_params
    )

    return redirect_to hotel_booking_path(current_hotel, @booking), alert: result.error unless result.success?

    if result.rejected?
      return render_checkout_required_response("Late checkout rejected. Complete checkout to resolve the booking.")
    end

    notice = result.charged? ? "Late checkout charge applied." : "Late checkout resolved without charge."
    offcanvas_transaction_response(
      destination: offcanvas_return_to(fallback: hotel_booking_path(current_hotel, @booking)),
      notice: notice
    )
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

  def late_checkout_params
    params.permit(:charge_type, :amount, :check_out, :charge_calculation, :custom_type, :custom_value)
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
      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = success_notice
          render_offcanvas_completion(checkout_success_path)
        end
        format.html { redirect_to hotel_booking_path(current_hotel, @booking), notice: success_notice }
      end
    else
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      set_audit_logs(@booking)

      respond_to do |format|
        format.turbo_stream do
          if booking_timeline_board_request?
            render turbo_stream: turbo_stream.append("booking_timeline_board", partial: "shared/toast", locals: { key: "alert", value: result.error })
          else
            flash.now[:alert] = result.error
            render "hotel_portal/bookings/show", formats: [ :html ], status: :unprocessable_content
          end
        end
        format.html do
          flash.now[:alert] = result.error
          render "hotel_portal/bookings/show", status: :unprocessable_content
        end
      end
    end
  end

  def booking_timeline_board_request?
    params[:source] == "booking_timeline_board" || request.referer&.include?("bookings/board")
  end

  def check_out_from_sheet(timestamp)
    @booking = current_hotel.bookings.includes(booking_folio: { folio_transactions: :user }).find(params[:id])
    error = nil
    if @booking.checkout_required? && timestamp.blank?
      return render_checkout_sheet_error("Check-out date and time can't be blank.")
    end

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
        options: { defer_side_effects: true }.merge(checkout_blocker_resolution_options)
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
    offcanvas_transaction_response(destination: checkout_success_path, notice: "Guest has been checked out.")
  end

  def post_checkout_settlement_payment
    return if checkout_payment_amount.blank?
    return OpenStruct.new(success?: true) if checkout_payment_amount.zero?

    return OpenStruct.new(success?: false, error: "Booking has no folio.") unless @booking.booking_folio
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("post_folio_payments", hotel: current_hotel)
    return OpenStruct.new(success?: false, error: "Checkout payment method is not supported.") unless checkout_payment_method == "cash"

    balance = @booking.booking_folio.outstanding_balance.to_d
    return OpenStruct.new(success?: true) unless balance.positive?
    return OpenStruct.new(success?: false, error: "Checkout payment cannot exceed the outstanding balance.") if checkout_payment_amount > balance

    Folios::PostStaffTransaction.call(
      folio: @booking.booking_folio,
      user: current_user,
      transaction_type: "payment",
      category: "cash",
      amount: checkout_payment_amount,
      description: checkout_payment_description,
      posting_date: current_hotel.current_business_date,
      options: checkout_blocker_resolution_options
    )
  end

  def checkout_blocker_resolution_options
    return {} unless @booking&.checkout_required?
    return {} unless current_hotel.current_business_date_record&.audit_blocked?

    audit = current_hotel.night_audits.where(business_date: current_hotel.current_business_date).order(created_at: :desc).first
    return {} unless audit

    {
      posting_source: "audit_blocker_resolution",
      correction_reason: "Resolve checkout-required night audit blocker",
      blocker_resolution: {
        night_audit_id: audit.id,
        blocker_type: "due_out_not_checked_out",
        booking_id: @booking.id
      }
    }
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
            transaction_return_to: offcanvas_return_to(fallback: hotel_booking_path(current_hotel, @booking))
          }
        )
      end
      format.html { redirect_to hotel_booking_transaction_check_out_path(current_hotel, @booking), notice: notice, status: :see_other }
    end
  end

  def dispatch_checkout_side_effects
    Bookings::WebhookTriggerService.new(@booking).trigger(:booking_completed)
    Notifications::Dispatcher.new(event: :booking_completed, booking: @booking).call
    SendInvoiceEmailJob.perform_later(@booking.id)
  end

  def checkout_success_path
    fallback = hotel_booking_path(current_hotel, @booking, checkout_success: true)
    return offcanvas_return_to(fallback: fallback) if params[:return_to].present?
    return board_hotel_bookings_path(current_hotel) if booking_timeline_board_request?

    fallback
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
