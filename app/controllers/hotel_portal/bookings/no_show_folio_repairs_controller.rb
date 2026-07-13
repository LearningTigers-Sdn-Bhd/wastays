# frozen_string_literal: true

class HotelPortal::Bookings::NoShowFolioRepairsController < HotelPortal::BaseController
  include OffcanvasTransactionCompletion

  before_action :authorize_repair!

  def create
    @booking = current_hotel.bookings.find(params[:id])
    result = Bookings::RepairNoShowTourismTax.call(booking: @booking, user: current_user)

    if result.success?
      offcanvas_transaction_response(
        destination: offcanvas_return_to(fallback: hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details")),
        notice: repair_notice(result)
      )
    else
      redirect_to hotel_booking_control_panel_path(current_hotel, @booking, tab: "booking_details"), alert: result.error
    end
  end

  private

  def authorize_repair!
    permitted = %w[manage_bookings post_folio_corrections].all? do |permission|
      current_user.has_permission?(permission, hotel: current_hotel)
    end
    raise Pundit::NotAuthorizedError unless permitted
  end

  def repair_notice(result)
    return "No-show folio already has no tourism tax to repair." if result.reversal_transactions.empty?

    notice = "Tourism tax of #{money(result.repaired_amount)} was removed from the no-show folio."
    return "#{notice} Settled folio closed." if result.closed_folios.any?

    "#{notice} Folio remains open because it has a non-zero balance."
  end

  def money(amount)
    "#{@booking.currency.presence || current_hotel.default_currency} #{format('%.2f', amount)}"
  end
end
