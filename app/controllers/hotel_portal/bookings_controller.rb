# frozen_string_literal: true

class HotelPortal::BookingsController < HotelPortal::BaseController
  include BookingAuditable

  before_action :authorize_view_bookings!, only: %i[index show]
  before_action :authorize_manage_bookings!, only: %i[update]

  def index
    @bookings = current_hotel.bookings.recent_first.includes(:booking_folio)

    @bookings = @bookings.search(params[:query]) if params[:query].present?
    @bookings = @bookings.where(status: params[:status]) if params[:status].present?
    @bookings = @bookings.checking_in_on(params[:check_in_date], current_hotel.hotel_time_zone) if params[:check_in_date].present?

    @bookings = @bookings.page(params[:page]).per(25)
    render "hotel_portal/bookings/index/index"
  end

  def show
    @booking = current_hotel.bookings
                            .includes(
                              booking_folio: [ :folio_transactions, :folio_forecasted_charges ],
                              booking_rooms: [ :room_type, :rate_plan ],
                              booking_guests: :guest,
                              booking_notes: :user
                            )
                            .find(params[:id])
    set_breadcrumbs
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    set_audit_logs(@booking)
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
          set_breadcrumbs
          set_audit_logs(@booking)
          @booking.errors.add(:base, result.errors.to_sentence)
          render :show, status: :unprocessable_content
        end
        format.json { render json: { success: false, errors: result.errors }, status: :unprocessable_content }
      end
    end
  end

  private

  def release_room_locks(booking)
    room_number = booking.hotel_snapshot.is_a?(Hash) ? (booking.hotel_snapshot["room_number"] || booking.hotel_snapshot.dig("assignment", "room_number")) : nil
    RoomLock.where(hotel: current_hotel, user: current_user, room_number: room_number).destroy_all if room_number.present?
  end

  def set_breadcrumbs
    override_breadcrumbs(
      { label: "Operations" },
      { label: "Bookings", path: hotel_bookings_path(current_hotel) },
      { label: @booking.confirmation_token, path: hotel_booking_path(current_hotel, @booking) },
      { label: "Booking Details", tab_label: true }
    )
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :checked_in_at, :checked_out_at,
      :guest_country, :guest_city, :guest_gender, :guest_document_type, :guest_government_id, :guest_update_intent,
      :room_type_id, :room_number, :check_in, :check_out, :adults, :children, :total_amount,
      :record_payment, :payment_method, :payment_amount, :payment_reference,
      :id_front, :id_back, :source, :internal_notes, :manual_rate_override, :existing_guest_id,
      :rate_plan_id, :apply_stop_sell_restriction, :apply_arrival_departure_restrictions, :apply_stay_length_restrictions,
      :guarantee_method,
      booking_rooms_attributes: [ :id, :room_type_id, :room_number, :rate_plan_id ]
    )
  end

  def authorize_view_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_bookings", hotel: current_hotel)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
