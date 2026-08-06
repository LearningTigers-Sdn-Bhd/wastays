# frozen_string_literal: true

class HotelPortal::Bookings::GuestRegistrationCardPdfsController < HotelPortal::BaseController
  before_action :authorize_view_guest_registration_cards!
  before_action :set_booking
  before_action :set_card

  def show
    presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking)
    pdf_bytes = GuestRegistrationCardPdfService.new(@card, @booking, presenter).generate

    send_data pdf_bytes,
      filename: "wastays-guest-registration-card-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def set_card
    @card = @booking.guest_registration_card || @booking.create_guest_registration_card!(hotel: current_hotel)
  end

  def authorize_view_guest_registration_cards!
    return if current_user.has_permission?("manage_bookings", hotel: current_hotel)
    return if current_user.has_permission?("view_reports", hotel: current_hotel)

    raise Pundit::NotAuthorizedError
  end
end
