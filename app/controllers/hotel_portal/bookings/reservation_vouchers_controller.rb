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

  # Every room in the group, one voucher per page. A booking that belongs to no group has
  # nothing to pack, so it falls back to its own voucher rather than erroring.
  def pack
    group_booking = @booking.group_booking
    return redirect_to hotel_booking_reservation_voucher_path(current_hotel, @booking) if group_booking.blank?

    pdf_bytes = Reports::Bookings::GenerateVoucherPack.new(group_booking).generate

    send_data pdf_bytes,
      filename: "wastays-reservation-vouchers-#{group_booking.formatted_reservation_number}.pdf",
      type: "application/pdf",
      disposition: "inline"
  rescue Reports::Bookings::GenerateVoucherPack::EmptyGroupError
    redirect_to hotel_booking_path(current_hotel, @booking), alert: "This group has no rooms to print."
  end

  private

  def set_booking
    @booking = current_hotel.bookings.includes(:group_booking).find(params[:booking_id])
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
