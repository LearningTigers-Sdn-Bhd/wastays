class HotelPortal::CheckedOutGuestsController < HotelPortal::BaseController
  def index
    redirect_to hotel_front_desk_path(current_hotel, checkout_params), status: :moved_permanently
  end

  private

  def checkout_params
    { tab: "checkout", view: "list", checkout_query: params[:query], checkout_page: params[:page] }.compact
  end
end
