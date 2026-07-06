# frozen_string_literal: true

class HotelPortal::Bookings::GuestsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    Booking.transaction do
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
      Bookings::RecordAuditLog.call!(
        auditable: @booking,
        user: current_user,
        action_type: "guest_added",
        old_value: {},
        new_value: guest.attributes.slice("name", "email", "phone", "country", "gender", "document_type")
      )
    end
    redirect_to hotel_booking_path(current_hotel, @booking), notice: "Guest added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to hotel_booking_path(current_hotel, @booking), alert: e.message
  end

  def destroy
    @booking = current_hotel.bookings.find(params[:id])
    bg = @booking.booking_guests.find_by!(id: params[:guest_id], is_primary: false)
    result = ::BookingGuests::Remove.call(booking_guest: bg, actor: current_user)
    redirect_to hotel_booking_path(current_hotel, @booking),
      result.success? ? { notice: "Guest removed." } : { alert: result.error }
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
