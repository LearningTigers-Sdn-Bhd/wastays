# frozen_string_literal: true

module HotelPortal
  class InHouseGuestsController < HotelPortal::BaseController
    def index
      redirect_to hotel_front_desk_path(current_hotel, in_house_params), status: :moved_permanently
    end

    private

    def in_house_params
      { tab: "in_house", view: "list", in_house_query: params[:query], room_assignment: params[:room_assignment], in_house_page: params[:page] }.compact
    end
  end
end
