# frozen_string_literal: true

module HotelPortal
  class FinancialsBaseController < BaseController
    layout "hotel_financials"

    helper HotelPortal::FinancialsNavigationHelper
  end
end
