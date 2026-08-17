# frozen_string_literal: true

class HotelPortal::Bookings::GuestRegistrationCardsController < HotelPortal::BaseController
  before_action :authorize_view_guest_registration_cards!, only: :show
  before_action :authorize_manage_bookings!, only: %i[update destroy]
  before_action :set_booking
  before_action :set_card

  def show
    @presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking)
  end

  def update
    result = Bookings::UpdateGuestRegistrationCard.call(
      card: @card,
      booking: @booking,
      params: guest_registration_card_params
    )

    if result.success?
      if params[:guest_registration_card][:signature_data_url].blank? && params[:guest_registration_card][:signer_name].blank?
        respond_to do |format|
          format.html { redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), notice: "Remarks and notes updated." }
          format.json { render json: { status: "success", message: "Remarks and notes updated." } }
        end
      else
        redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), notice: "Guest registration card signed."
      end
    else
      if result.error.in?(%i[already_signed terms_missing])
        redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), alert: result.message
      else
        @presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking)
        render :show, status: :unprocessable_content
      end
    end
  end

  def destroy
    Bookings::RemoveRegistrationCardSignature.call(card: @card)
    redirect_to hotel_booking_guest_registration_card_path(current_hotel, @booking), notice: "Guest registration card signature removed."
  end

  private

  def set_booking
    @booking = current_hotel.bookings.find(params[:booking_id])
  end

  def set_card
    @card = @booking.guest_registration_card || @booking.create_guest_registration_card!(hotel: current_hotel)
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
