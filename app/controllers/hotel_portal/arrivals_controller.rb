class HotelPortal::ArrivalsController < HotelPortal::BaseController
  def index
    redirect_to hotel_front_desk_path(current_hotel, arrivals_params), status: :moved_permanently
  end

  private

  def arrivals_params
    { tab: "arrivals", view: "list", arrival_date: params[:date], arrival_q: params[:q], arrival_page: params[:page] }.compact
  end
end
