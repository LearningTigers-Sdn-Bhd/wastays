# frozen_string_literal: true

module CorporatePortal
  # An agent correcting the guests on one of their bookings before arrival.
  # One booking is one room, so a multi-room stay is edited room by room.
  class BookingGuestsController < CorporatePortal::BaseController
    before_action :load_booking
    before_action :require_editable!

    def edit
      @guests = @booking.booking_guests.includes(:guest).order(Arel.sql("booking_guests.role = 'primary' DESC"), :id)
    end

    def update
      result = UpdateAgentBookingGuests.call(booking: @booking, user: current_user, guests: guests_params)

      if result.success?
        redirect_to corporate_booking_path(@booking), notice: "Guest details updated."
      else
        @guests = @booking.booking_guests.includes(:guest).order(Arel.sql("booking_guests.role = 'primary' DESC"), :id)
        flash.now[:alert] = result.errors.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    private

    # Scoped to this account, so another agency's booking is not found rather
    # than forbidden.
    def load_booking
      @booking = corporate_bookings.includes(:hotel).find(params[:booking_id])
    end

    def require_editable!
      return if UpdateAgentBookingGuests.editable?(@booking)

      redirect_to corporate_booking_path(@booking), alert: "Guest details can only be changed before arrival."
    end

    # Keyed by booking guest id, or "newN" for a companion added here.
    def guests_params
      params.fetch(:guests, {}).permit(
        params.fetch(:guests, {}).keys.index_with { UpdateAgentBookingGuests::FIELDS }
      )
    end
  end
end
