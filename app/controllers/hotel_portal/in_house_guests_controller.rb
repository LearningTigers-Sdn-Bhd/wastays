# frozen_string_literal: true

module HotelPortal
  class InHouseGuestsController < HotelPortal::BaseController
    def index
      @query_service = HotelPortal::InHouseGuestsQuery.new(
        hotel: current_hotel,
        params: params
      )

      @all_in_house_guests = @query_service.call
      @in_house_guests = @all_in_house_guests.page(params[:page]).per(25)

      @in_house_count = @query_service.in_house_count
      @check_outs_today_count = @query_service.check_outs_today_count

      @query = params[:query].to_s.strip
      @room_assignment = params[:room_assignment].to_s
    end
  end
end
