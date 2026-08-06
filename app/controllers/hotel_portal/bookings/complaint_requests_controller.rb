# frozen_string_literal: true

class HotelPortal::Bookings::ComplaintRequestsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def resolve
    @booking = current_hotel.bookings.find(params[:id])
    updater = ::HotelPortal::Requests::StatusUpdater.new(
      hotel: current_hotel,
      kind: "complaint",
      request_id: params[:complaint_request_id],
      status: "resolved"
    )

    if updater.call
      redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "housekeeping_requests"), notice: "Complaint resolved."
    else
      redirect_to hotel_booking_workspace_path(current_hotel, @booking, tab: "housekeeping_requests"), alert: "Failed to update request."
    end
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
