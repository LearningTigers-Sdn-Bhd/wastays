module Public
  module Concierge
    module Stays
      class OverviewController < BaseController
        def show
          @presenter = stay_presenter
          @booking = stay_booking
        end
      end
    end
  end
end
