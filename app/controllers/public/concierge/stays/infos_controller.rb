module Public
  module Concierge
    module Stays
      # The Property Guide pages and the Wi-Fi page, reached from the stay page.
      # The same pages as the public ones, plus the Wi-Fi the stay may use.
      class InfosController < BaseController
        include ConciergeContactDetails
        def show
          @presenter = stay_presenter
          @section = ::Concierge::PropertyInfoPresenter::PAGES.keys.find { |key| key == params[:section] } || "property"
          @info = ::Concierge::PropertyInfoPresenter.new(hotel: @hotel, booking: stay_booking)
          @maps_link = maps_link
        end
      end
    end
  end
end
