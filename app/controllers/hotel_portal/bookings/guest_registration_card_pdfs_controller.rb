# frozen_string_literal: true

class HotelPortal::Bookings::GuestRegistrationCardPdfsController < HotelPortal::BaseController
  before_action :authorize_view_guest_registration_cards!
  before_action :set_booking
  before_action :set_card

  def show
    unless @card.ready_for_guest?
      return redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking, booking_guest_id: params[:booking_guest_id]),
        alert: "Set a Terms & Conditions policy in Settings before printing this card."
    end

    presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking, booking_guest_id: params[:booking_guest_id])
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
    booking_guest = if params[:booking_guest_id].present?
                      @booking.booking_guests.find { |bg| bg.id.to_s == params[:booking_guest_id].to_s }
    else
                      @booking.booking_guests.find(&:primary?)
    end

    @card = if booking_guest
              booking_guest.guest_registration_card || booking_guest.build_guest_registration_card(hotel: current_hotel, booking: @booking)
    else
              @booking.guest_registration_card || @booking.build_guest_registration_card(hotel: current_hotel)
    end
  end

  def authorize_view_guest_registration_cards!
    return if current_user.has_permission?("manage_bookings", hotel: current_hotel)
    return if current_user.has_permission?("view_reports", hotel: current_hotel)

    raise Pundit::NotAuthorizedError
  end
end
