# frozen_string_literal: true

class HotelPortal::Bookings::ReservationVouchersController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!
  before_action :set_booking

  def show
    pdf_bytes = Reports::Bookings::GenerateVoucher.new(@booking).generate

    send_data pdf_bytes,
      filename: "wastays-reservation-voucher-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
