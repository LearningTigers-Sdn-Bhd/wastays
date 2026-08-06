# frozen_string_literal: true

# Renders a single booking-creation room row on demand so each row's PanelsUI
# SelectMenus are real, server-rendered controls that Stimulus hydrates on
# insertion — instead of cloning a <template> string (which Tom Select / the
# select controllers cannot initialise).
class HotelPortal::Bookings::RoomRowsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def show
    @room_types = current_hotel.room_types.order(:name)
    render partial: "hotel_portal/bookings/actions/booking_creations/partials/room_row",
      locals: { index: params[:index].to_s, values: {} }
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
