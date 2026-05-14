class Public::PreCheckinsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  before_action :set_pre_checkin
  before_action :set_booking
  before_action :set_hotel
  before_action :prepare_form_values, only: :show

  def show
    @presenter = Public::PreCheckinPresenter.new(@pre_checkin)
  end

  def update
    result = GuestArrival::ProcessPreCheckin.new(
      booking: @booking,
      pre_checkin: @pre_checkin,
      params: booking_params
    ).call

    if result.success?
      redirect_to pre_checkin_path(@pre_checkin.token), notice: "Pre-check-in completed successfully!"
    else
      prepare_form_values(result.submitted_arrival_time, result.submitted_government_id)
      @booking.errors.add(:base, result.message)
      render :show, status: :unprocessable_content
    end
  end

  def cancel
    result = GuestArrival::CancelPreCheckin.new(booking: @booking, pre_checkin: @pre_checkin).call

    if result.success?
      redirect_to booking_path(@booking.confirmation_token), notice: "Pre-check-in cancelled."
    else
      redirect_to booking_path(@booking.confirmation_token), alert: result.message
    end
  end

  private

  def set_pre_checkin
    @pre_checkin = PreCheckin.find_by!(token: params[:token])
  end

  def set_booking
    @booking = @pre_checkin.booking
  end

  def set_hotel
    @hotel = @booking.hotel
  end

  def prepare_form_values(arrival_time = nil, government_id = nil)
    metadata = @pre_checkin.metadata || {}
    @booking.estimated_arrival_time = arrival_time.presence || metadata["estimated_arrival_time"].presence
    @booking.guest_government_id = government_id.presence || metadata["guest_government_id"].presence || @booking.primary_guest&.government_id
  end

  def booking_params
    params.require(:booking).permit(
      :guest_name,
      :guest_email,
      :guest_phone,
      :guest_country,
      :guest_document_type,
      :guest_government_id,
      :id_front,
      :id_back,
      :estimated_arrival_time
    )
  end
end
