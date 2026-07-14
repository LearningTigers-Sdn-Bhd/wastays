# frozen_string_literal: true

class HotelPortal::Bookings::TourismTaxVouchersController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!
  before_action :set_booking

  def show
    unless @booking.tourism_tax?
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "This booking has no tourism tax obligation."
      return
    end

    unless @booking.tourism_tax_voucher_number?
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "Issue the tourism tax voucher before printing it."
      return
    end

    pdf_bytes = TourismTaxVoucherPdfService.new(booking: @booking, printed_by: current_user).generate

    send_data pdf_bytes,
      filename: "wastays-tourism-tax-voucher-#{@booking.formatted_tourism_tax_voucher_number}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  def issue
    unless @booking.tourism_tax?
      redirect_to hotel_booking_path(current_hotel, @booking), alert: "This booking has no tourism tax obligation."
      return
    end

    @booking.assign_tourism_tax_voucher_number!(user: current_user)
    redirect_to hotel_booking_tourism_tax_voucher_path(current_hotel, @booking)
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
