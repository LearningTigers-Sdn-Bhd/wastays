# frozen_string_literal: true

module CorporatePortal
  # An agent cancelling their own booking.
  #
  # Its own resource rather than BookingsController#destroy: nothing is deleted.
  # The stay becomes cancelled history and the rooms go back on sale.
  class BookingCancellationsController < CorporatePortal::BaseController
    before_action :load_booking

    def new
      @cancellation = CancelAgentBooking.new(booking: @booking, user: current_user)
      redirect_to corporate_booking_path(@booking), alert: @cancellation.refusal_reason if @cancellation.refusal_reason.present?
    end

    def create
      result = CancelAgentBooking.call(booking: @booking, user: current_user)

      if result.success?
        redirect_to corporate_booking_path(@booking),
                    notice: "#{ActionController::Base.helpers.pluralize(result.bookings.size, 'room')} cancelled and returned to sale."
      else
        redirect_to corporate_booking_path(@booking), alert: result.error
      end
    end

    private

    # Scoped to this account, so another agency's booking is not found rather
    # than forbidden.
    def load_booking
      @booking = corporate_bookings.includes(:hotel, :hotel_corporate_account).find(params[:booking_id])
    end
  end
end
