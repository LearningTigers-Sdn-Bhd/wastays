module Public
  module Concierge
    class HomeController < BaseController
      def show
        render "show_mobile" if mobile_request?
      end

      def book
        redirect_to hotel_path(@hotel.unique_id, @hotel.public_id)
      end
    end
  end
end
