# frozen_string_literal: true

class HotelPortal::Bookings::CheckInsController < HotelPortal::BaseController
  include BookingAuditable
  include OffcanvasTransactionCompletion
  include GroupLifecycleTargeting

  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    timestamp = transition_timestamp(:checked_in_at)

    if @booking.checked_in? && params[:retroactive_reason].blank?
      error_msg = "Reason to change is required."
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      set_audit_logs(@booking)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = error_msg
          render_offcanvas_completion(check_in_success_path)
        end
        format.html { redirect_to check_in_success_path, alert: error_msg, status: :see_other }
      end
      return
    end

    return batch_check_in(timestamp) if selected_lifecycle_batch?(@booking)

    options = {}
    if params[:booking].present?
      options[:attributes] = booking_params.except(:checked_in_at, :checked_out_at)
    end

    if @booking.checked_in?
      options[:reason] = params[:retroactive_reason]
    elsif params[:override_night_audit] == "1"
      options[:override_night_audit] = true
      options[:reason] = params[:retroactive_reason]
    end
    options[:security_deposit] = security_deposit_options if collect_security_deposit?

    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: "checked_in",
      timestamp: timestamp,
      user: current_user,
      options: options
    ).call

    if result.success?
      release_room_locks(@booking)

      respond_to do |format|
        format.turbo_stream do
          flash[:notice] = "Guest checked in successfully."
          render_offcanvas_completion(check_in_success_path)
        end
        format.html { redirect_to check_in_success_path, notice: "Guest checked in successfully." }
      end
    else
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      set_audit_logs(@booking)

      respond_to do |format|
        format.turbo_stream do
          if booking_timeline_board_request?
            render turbo_stream: toast_stream(result.error, type: :error)
          else
            flash[:alert] = result.error
            render_offcanvas_completion(check_in_success_path)
          end
        end
        format.html do
          redirect_to check_in_success_path, alert: result.error, status: :see_other
        end
      end
    end
  end

  private

  def batch_check_in(timestamp)
    if @booking.checked_in? && params[:retroactive_reason].blank?
      raise BatchTargetError, "Reason to change is required."
    end

    action = @booking.checked_in? ? :edit_check_in : :check_in
    bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: action)
    options = {}
    if @booking.checked_in?
      options[:reason] = params[:retroactive_reason]
    elsif params[:override_night_audit] == "1"
      options[:override_night_audit] = true
      options[:reason] = params[:retroactive_reason]
    end

    ActiveRecord::Base.transaction do
      bookings.each do |booking|
        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "checked_in",
          timestamp: timestamp.presence || Time.current,
          user: current_user,
          options: options
        ).call
        raise BatchTargetError, result.error unless result.success?
      end
    end

    bookings.each { |booking| release_room_locks(booking) }
    offcanvas_transaction_response(
      destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
      notice: batch_lifecycle_notice(bookings, "checked in")
    )
  rescue BatchTargetError => e
    redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: e.message, status: :see_other
  end

  def transition_timestamp(attribute)
    params[attribute].presence || booking_params[attribute].presence
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :checked_in_at, :checked_out_at,
      :guest_country, :guest_gender, :guest_document_type, :guest_government_id, :guest_update_intent,
      :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
      :guarantee_method, :tourism_tax_collected,
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

  def release_room_locks(booking)
    room_number = booking.hotel_snapshot.is_a?(Hash) ? (booking.hotel_snapshot["room_number"] || booking.hotel_snapshot.dig("assignment", "room_number")) : nil
    RoomLock.where(hotel: current_hotel, user: current_user, room_number: room_number).destroy_all if room_number.present?
  end

  def check_in_success_path
    fallback = hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")
    return offcanvas_return_to(fallback: fallback) if params[:return_to].present?
    return board_hotel_bookings_path(current_hotel) if booking_timeline_board_request?

    fallback
  end

  def booking_timeline_board_request?
    params[:source] == "booking_timeline_board" || request.referer&.include?("bookings/board")
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
