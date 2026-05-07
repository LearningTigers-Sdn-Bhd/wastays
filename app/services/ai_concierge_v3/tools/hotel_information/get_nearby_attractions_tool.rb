module AiConciergeV3
  module Tools
    module HotelInformation
      class GetNearbyAttractionsTool
        def initialize(hotel:)
          @hotel = hotel
        end

        def call
          {
            "success" => true,
            "attractions" => attractions.map do |attraction|
              {
                "name" => attraction.name,
                "description" => attraction.description,
                "address" => attraction.address,
                "city" => attraction.city,
                "country" => attraction.country
              }
            end
          }
        end

        private

        attr_reader :hotel

        def attractions
          @attractions ||= hotel.nearby_attractions.order(created_at: :asc)
        end
      end
    end
  end
end
