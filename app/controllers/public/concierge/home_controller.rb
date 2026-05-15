module Public
  module Concierge
    class HomeController < BaseController
      def show; end

      def book
        redirect_to hotel_path(@hotel.slug)
      end
    end
  end
end
