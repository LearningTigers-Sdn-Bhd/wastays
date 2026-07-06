# frozen_string_literal: true

class HotelPortal::Bookings::GuestRegistrationCardsController < HotelPortal::BaseController
  before_action :authorize_view_guest_registration_cards!, only: :show
  before_action :authorize_manage_bookings!, only: %i[update destroy]
  before_action :set_booking
  before_action :set_card

  def show
  end

  def update
    @card.assign_attributes(card_params.merge(status: "signed", signed_at: Time.current, terms_snapshot: @card.capture_terms_snapshot_preview))

    if @card.save
      redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), notice: "Guest registration card signed."
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @card.update!(status: "draft", signer_name: nil, signature_data_url: nil, signed_at: nil)
    redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), notice: "Guest registration card signature removed."
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def set_card
    @card = @booking.guest_registration_card || @booking.create_guest_registration_card!(hotel: current_hotel)
  end

  def card_params
    params.require(:guest_registration_card).permit(:signer_name, :signature_data_url)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end

  def authorize_view_guest_registration_cards!
    return if current_user.has_permission?("manage_bookings", hotel: current_hotel)
    return if current_user.has_permission?("view_reports", hotel: current_hotel)

    raise Pundit::NotAuthorizedError
  end
end
