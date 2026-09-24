module Public
  module Concierge
    module Stays
      class OverviewController < BaseController
        def show
          @presenter = stay_presenter
          @booking = stay_booking
          @info = ::Concierge::PropertyInfoPresenter.new(hotel: @hotel, booking: @booking)
        end
      end
    end
  end
end
