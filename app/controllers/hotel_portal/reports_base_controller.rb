# frozen_string_literal: true

module HotelPortal
  class ReportsBaseController < BaseController
    layout "hotel_reports"

    helper HotelPortal::ReportsNavigationHelper
  end
end
