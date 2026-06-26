# frozen_string_literal: true

class HotelPortal::Bookings::NoShowsController < HotelPortal::BaseController
  include OffcanvasTransactionCompletion

  before_action :authorize_manage_bookings!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::FinalizeNoShow.call(booking: @booking, user: current_user)

    if result.success?
      offcanvas_transaction_response(
        destination: offcanvas_return_to(fallback: hotel_booking_path(current_hotel, @booking)),
        notice: no_show_notice(result)
      )
    else
      render_failure(result.error)
    end
  end

  private

  def no_show_notice(result)
    notice = "Booking marked as no-show. Tourism tax was not charged."
    return "#{notice} Settled folio closed." if result.closed_folios.any?
    return notice if result.skipped_folios.empty?

    balances = result.skipped_folios.map do |entry|
      "#{entry.folio.display_name}: #{entry.folio.currency} #{format('%.2f', entry.balance)}"
    end
    "#{notice} Folio remains open (#{balances.to_sentence})."
  end

  def render_failure(error)
    @booking.errors.add(:base, error)
    @presenter = HotelPortal::BookingPresenter.new(@booking, current_hotel)
    @transaction_return_to = offcanvas_return_to(fallback: hotel_booking_path(current_hotel, @booking))

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "offcanvas_drawer",
          partial: "hotel_portal/bookings/transactions/mark_no_show/sheet"
        ), status: :unprocessable_content
      end
      format.html { redirect_to hotel_booking_path(current_hotel, @booking), alert: error }
    end
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
