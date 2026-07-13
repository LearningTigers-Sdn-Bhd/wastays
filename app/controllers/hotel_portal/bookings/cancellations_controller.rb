# frozen_string_literal: true

class HotelPortal::Bookings::CancellationsController < HotelPortal::BaseController
  include OffcanvasTransactionCompletion
  include GroupLifecycleTargeting

  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    if params[:cancellation_reason].blank?
      @booking.errors.add(:base, "Cancellation reason is required.")
      @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
      @transaction_return_to = offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"))
      return render "hotel_portal/bookings/transactions/cancel_booking/offcanvas", status: :unprocessable_content
    end

    return batch_cancel if selected_lifecycle_batch?(@booking)

    result = Bookings::TransitionStatus.new(
      booking: @booking,
      status: "cancelled",
      user: current_user,
      options: { reason: params[:cancellation_reason] }
    ).call

    if result.success?
      offcanvas_transaction_response(
        destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
        notice: "Booking cancelled successfully."
      )
    else
      redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: result.error
    end
  end

  private

  def batch_cancel
    bookings = selected_lifecycle_bookings(fallback_booking: @booking, action: :cancel)

    ActiveRecord::Base.transaction do
      bookings.each do |booking|
        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "cancelled",
          user: current_user,
          options: { reason: params[:cancellation_reason] }
        ).call
        raise BatchTargetError, result.error unless result.success?
      end
    end

    offcanvas_transaction_response(
      destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
      notice: batch_lifecycle_notice(bookings, "cancelled")
    )
  rescue BatchTargetError => e
    redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: e.message, status: :see_other
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
