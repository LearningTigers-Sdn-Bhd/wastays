module Public
  module Concierge
    class HomeController < BaseController
      def show
        render "show_mobile" if mobile_request?
      end

      def book
        redirect_to hotel_path(@hotel)
      end
    end
  end
end
