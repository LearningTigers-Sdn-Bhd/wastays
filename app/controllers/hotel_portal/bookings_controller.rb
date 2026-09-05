# frozen_string_literal: true

# LEGACY: frozen pending booking-workspace migration. Do not add features here.

class HotelPortal::BookingsController < HotelPortal::BaseController
  include BookingAuditable

  before_action :authorize_view_bookings!, only: %i[index show]
  before_action :authorize_manage_bookings!, only: %i[update]

  def index
    redirect_to hotel_front_desk_path(current_hotel, legacy_index_params), status: :moved_permanently
  end

  def show
    booking = current_hotel.bookings.find(params[:id])
    tab = { "requests" => "housekeeping_requests", "history" => "audit_trails" }.fetch(params[:tab].to_s, "booking_details")
    redirect_to hotel_booking_workspace_path(current_hotel, booking, tab: tab), status: :moved_permanently
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
        format.html { redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "booking_details"), notice: "Booking updated successfully." }
        format.json { render json: { success: true, booking: @booking } }
      end
    else
      respond_to do |format|
        format.html { render plain: result.errors.to_sentence, status: :unprocessable_content }
        format.json { render json: { success: false, errors: result.errors }, status: :unprocessable_content }
      end
    end
  end

  private

  def legacy_index_params
    {
      tab: "bookings",
      view: legacy_view,
      booking_query: params[:query],
      booking_status: params[:status],
      booking_check_in_date: params[:check_in_date],
      booking_page: params[:page]
    }.compact
  end

  def release_room_locks(booking)
    room_number = booking.hotel_snapshot.is_a?(Hash) ? (booking.hotel_snapshot["room_number"] || booking.hotel_snapshot.dig("assignment", "room_number")) : nil
    RoomLock.where(hotel: current_hotel, user: current_user, room_number: room_number).destroy_all if room_number.present?
  end

  def booking_params
    params.fetch(:booking, {}).permit(
      :guest_name, :guest_email, :guest_phone, :checked_in_at, :checked_out_at,
      :guest_country, :guest_city, :guest_state_code, :guest_postal_code, :guest_address_country,
      :guest_home_address, :guest_tin, :guest_gender, :guest_document_type, :guest_government_id,
      :guest_passport_number, :guest_date_of_birth, :guest_update_intent,
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
