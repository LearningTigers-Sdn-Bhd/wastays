class Hotel::Bookings::BookingNotesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def create
    @booking = current_hotel.bookings.find(params[:booking_id])
    @note = @booking.booking_notes.build(note_params)
    @note.user = current_user

    if @note.save
      redirect_to hotel_booking_path(@booking), notice: "Note added."
    else
      redirect_to hotel_booking_path(@booking), alert: "Failed to add note."
    end
  end

  private

  def note_params
    params.require(:booking_note).permit(:body)
  end
end
