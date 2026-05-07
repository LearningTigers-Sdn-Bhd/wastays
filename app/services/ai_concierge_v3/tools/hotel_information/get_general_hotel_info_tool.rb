module AiConciergeV3
  module Tools
    module HotelInformation
      class GetGeneralHotelInfoTool
        def initialize(hotel:)
          @hotel = hotel
        end

        def call
          {
            "success" => true,
            "name" => hotel.name,
            "address" => hotel.address,
            "city" => hotel.city,
            "country" => hotel.country,
            "star_rating" => hotel.star_rating,
            "amenities" => amenity_names,
            "summary_text" => summary_text
          }
        end

        private

        attr_reader :hotel

        def summary_text
          parts = [ hotel.name ]
          parts << "is a #{hotel.star_rating}-star hotel" if hotel.star_rating.present?

          location = [ hotel.address, hotel.city, hotel.country ].compact_blank.join(", ")
          parts << "located at #{location}" if location.present?

          parts.join(" ")
        end

        def amenity_names
          lookup = Hotel::HOTEL_AMENITIES.index_by { |amenity| amenity[:id] }

          Array(hotel.amenities).filter_map do |amenity_id|
            lookup[amenity_id]&.fetch(:name)
          end
        end
      end
    end
  end
end
