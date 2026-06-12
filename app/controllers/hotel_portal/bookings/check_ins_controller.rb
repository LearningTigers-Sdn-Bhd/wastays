# frozen_string_literal: true

class HotelPortal::Bookings::CheckInsController < HotelPortal::BaseController
  include BookingAuditable
  include OffcanvasTransactionCompletion

  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    timestamp = transition_timestamp(:checked_in_at)

    options = {}
    if params[:booking].present?
      options[:attributes] = booking_params.except(:checked_in_at, :checked_out_at)
    end

    if params[:override_night_audit] == "1"
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

  private

  def transition_timestamp(attribute)
    params[attribute].presence || booking_params[attribute].presence
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :checked_in_at, :checked_out_at,
      :guest_country, :guest_gender, :guest_document_type, :guest_government_id, :guest_update_intent,
      :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount
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
    fallback = hotel_booking_path(current_hotel, @booking)
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
