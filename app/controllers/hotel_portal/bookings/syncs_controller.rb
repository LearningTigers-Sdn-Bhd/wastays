# frozen_string_literal: true

class HotelPortal::Bookings::SyncsController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!

  def create
    result = ChannelManagers::FetchBookingsService.new(hotel: current_hotel).call

    if result.success?
      redirect_to hotel_front_desk_path(current_hotel, tab: "bookings", view: "list"), notice: result.message
    else
      redirect_to hotel_front_desk_path(current_hotel, tab: "bookings", view: "list"), alert: result.message
    end
  end

  private

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
