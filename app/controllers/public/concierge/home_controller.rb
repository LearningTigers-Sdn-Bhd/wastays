module Public
  module Concierge
    class HomeController < BaseController
      # One responsive template, so the tiles a guest sees do not depend on how
      # their user agent string is read.
      def show
        @info = ::Concierge::PropertyInfoPresenter.new(hotel: @hotel)
      end

      def book
        redirect_to hotel_path(@hotel.unique_id, @hotel.public_id)
      end
    end
  end
end
