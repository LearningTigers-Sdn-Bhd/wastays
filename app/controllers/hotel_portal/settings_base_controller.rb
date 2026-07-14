# frozen_string_literal: true

module HotelPortal
  class SettingsBaseController < BaseController
    layout "hotel_settings"

    helper HotelPortal::SettingsNavigationHelper
  end
end
