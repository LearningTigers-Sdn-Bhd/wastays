module Public
  module Concierge
    # The Property Guide pages: what the property has told guests in Guest
    # Content. One action serves every page; the route allows only known
    # sections. No stay is known here, so there is no Wi-Fi.
    class InfoController < BaseController
      include ConciergeContactDetails
      def show
        @section = params.fetch(:section, "property")
        @info = ::Concierge::PropertyInfoPresenter.new(hotel: @hotel)
        @maps_link = maps_link
      end
    end
  end
end
