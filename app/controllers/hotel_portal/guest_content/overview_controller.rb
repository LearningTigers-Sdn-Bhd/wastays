# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class OverviewController < HotelPortal::GuestContent::BaseController
      def index
        @presenter = HotelPortal::GuestContent::OverviewPresenter.new(hotel: @hotel)
      end
    end
  end
end
