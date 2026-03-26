module HotelPortal
  class BaseController < ApplicationController
    layout "hotel"
    before_action :authenticate_user!
    before_action :ensure_hotel_access!
  end
end
