# frozen_string_literal: true

class HotelPortal::Bookings::GuestRegistrationCardsController < HotelPortal::BaseController
  before_action :authorize_view_guest_registration_cards!, only: :show
  before_action :authorize_manage_bookings!, only: %i[update destroy]
  before_action :set_booking
  before_action :set_card

  def show
    @presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking, booking_guest_id: params[:booking_guest_id])
  end

  def update
    result = Bookings::UpdateGuestRegistrationCard.call(
      card: @card,
      booking: @booking,
      params: guest_registration_card_params,
      booking_guest_id: params[:booking_guest_id]
    )

    if result.success?
      if params.dig(:guest_registration_card, :signature_data_url).blank? && params.dig(:guest_registration_card, :signer_name).blank?
        respond_to do |format|
          format.html { redirect_to grc_redirect_path, notice: "Remarks and notes updated." }
          format.json { render json: { status: "success", message: "Remarks and notes updated." } }
        end
      else
        redirect_to grc_redirect_path, notice: "Guest registration card signed."
      end
    else
      if result.error.in?(%i[already_signed terms_missing])
        redirect_to grc_redirect_path, alert: result.message
      else
        @presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking, booking_guest_id: params[:booking_guest_id])
        render :show, status: :unprocessable_content
      end
    end
  end

  def destroy
    Bookings::RemoveRegistrationCardSignature.call(card: @card)
    redirect_to grc_redirect_path, notice: "Guest registration card signature removed."
  end

  private

  def grc_redirect_path
    hotel_booking_guest_registration_card_path(current_hotel, @booking, booking_guest_id: params[:booking_guest_id].presence)
  end

  def set_booking
    @booking = current_hotel.bookings.includes(:guest_registration_card, booking_guests: :guest_registration_card).find(params[:booking_id])
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

  def guest_registration_card_params
    params.require(:guest_registration_card).permit(
      :signer_name,
      :signature_data_url,
      :special_requests,
      :internal_notes
    )
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
