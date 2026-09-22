module Public
  module Concierge
    module Stays
      class OverviewController < BaseController
        def show
          @booking = stay_booking
        end
      end
    end
  end
end
