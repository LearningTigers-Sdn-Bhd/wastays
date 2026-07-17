class HotelPortal::CheckedOutGuestsController < HotelPortal::BaseController
  def index
    redirect_to hotel_front_desk_path(current_hotel, departures_params), status: :moved_permanently
  end

  private

  def departures_params
    { tab: "departures", view: "list", departure_query: params[:query], departure_page: params[:page] }.compact
  end
end
