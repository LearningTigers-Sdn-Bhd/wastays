class Public::PreCheckinsController < ApplicationController
  skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

  before_action :set_pre_checkin
  before_action :set_booking
  before_action :set_hotel
  before_action :prepare_form_values, only: :show

  def show; end

  def update
    if @pre_checkin.completed?
      redirect_to pre_checkin_path(@pre_checkin.token), notice: "Pre-check-in was already completed."
      return
    end

    submitted_params = booking_params.to_h
    submitted_government_id = submitted_params.delete("guest_government_id")
    submitted_arrival_time = submitted_params.delete("estimated_arrival_time")

    @booking.estimated_arrival_time = submitted_arrival_time

    ActiveRecord::Base.transaction do
      unless @booking.update(submitted_params)
        raise ActiveRecord::RecordInvalid.new(@booking)
      end

      guest_result = GuestArrival::CreateOrMatchGuest.new(
        name: @booking.guest_name,
        email: @booking.guest_email,
        phone: @booking.guest_phone,
        government_id: submitted_government_id,
        country: @booking.guest_country,
        document_type: @booking.guest_document_type
      ).call

      primary_booking_guest = @booking.booking_guests.find_or_initialize_by(is_primary: true)
      primary_booking_guest.guest = guest_result.guest
      primary_booking_guest.save!

      @pre_checkin.update!(
        status: "completed",
        completed_at: Time.current,
        document_status: "verified",
        signature_status: "signed",
        metadata: (@pre_checkin.metadata || {}).merge(
          guest_government_id: submitted_government_id,
          estimated_arrival_time: submitted_arrival_time,
          submitted_at: Time.current.iso8601
        )
      )

      @booking.update!(pre_checkin_status: "completed")
    end

    redirect_to pre_checkin_path(@pre_checkin.token), notice: "Pre-check-in completed successfully!"
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    prepare_form_values(submitted_arrival_time, submitted_government_id)
    @booking.errors.add(:base, e.message)
    render :show, status: :unprocessable_content
  end

  def cancel
    if @pre_checkin.completed?
      redirect_to booking_path(@booking.confirmation_token), alert: "Completed pre-check-in cannot be cancelled."
      return
    end

    @pre_checkin.update!(
      status: "pending",
      completed_at: nil,
      document_status: "pending",
      signature_status: "pending"
    )
    @booking.update!(pre_checkin_status: "pending")

    redirect_to booking_path(@booking.confirmation_token), notice: "Pre-check-in cancelled."
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
      :estimated_arrival_time
    )
  end
end
