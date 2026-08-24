module AiConcierge
  module Tools
    module HotelInformation
      class GetNearbyAttractionsTool
        def initialize(hotel:)
          @hotel = hotel
        end

        def call
          {
            "success" => true,
            "attractions" => nearby_links.map do |link|
              attraction = link.attraction
              {
                "name" => attraction.name,
                "description" => link.guest_description,
                "address" => attraction.address,
                "city" => attraction.city,
                "country" => attraction.country,
                "google_maps_url" => attraction.google_maps_url,
                "distance_km" => link.distance_from(hotel)
              }
            end
          }
        end

        private

        attr_reader :hotel

        def nearby_links
          @nearby_links ||= hotel.hotel_nearby_attractions
            .includes(:attraction)
            .joins(:attraction)
            .where(attractions: { status: %w[approved pending] })
            .order(:created_at)
        end
      end
    end
  end
end
