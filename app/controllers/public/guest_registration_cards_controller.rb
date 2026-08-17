# frozen_string_literal: true

class Public::GuestRegistrationCardsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  before_action :set_card
  before_action :set_booking
  before_action :set_hotel
  before_action :set_presenter, only: %i[show update]

  def show
  end

  def update
    result = Bookings::UpdateGuestRegistrationCard.call(
      card: @card,
      booking: @booking,
      params: guest_registration_card_params
    )

    if result.success?
      redirect_to guest_registration_card_path(@card.public_token), notice: "Thank you — your signature has been recorded."
    elsif result.error.in?(%i[already_signed terms_missing])
      redirect_to guest_registration_card_path(@card.public_token), alert: result.message
    else
      @card.errors.add(:base, result.message) if result.message.present?
      set_presenter
      render :show, status: :unprocessable_content
    end
  end

  # The PDF is generated the same way the front desk's own print action does —
  # a browser request, not a background job — which sidesteps whatever made
  # the emailed attachment come out unreadable.
  def pdf
    unless @card.signed?
      return redirect_to guest_registration_card_path(@card.public_token),
        alert: "Sign the card first — the PDF is available once it's signed."
    end

    presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking)
    pdf_bytes = GuestRegistrationCardPdfService.new(@card, @booking, presenter).generate

    send_data pdf_bytes,
      filename: "wastays-guest-registration-card-#{@booking.confirmation_token}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  private

  def set_card
    @card = GuestRegistrationCard.find_by!(public_token: params[:token])
  end

  def set_booking
    @booking = @card.booking
  end

  def set_hotel
    @hotel = @card.hotel
  end

  def set_presenter
    @presenter = HotelPortal::GuestRegistrationCardPresenter.new(@card, @booking)
  end

  def guest_registration_card_params
    params.require(:guest_registration_card).permit(:signer_name, :signature_data_url)
  end
end
