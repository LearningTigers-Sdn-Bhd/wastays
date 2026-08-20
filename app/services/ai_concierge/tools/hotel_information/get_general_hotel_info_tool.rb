module AiConcierge
  module Tools
    module HotelInformation
      class GetGeneralHotelInfoTool
        def initialize(hotel:, query: nil, hints: Retrieval::QueryHints.none)
          @hotel = hotel
          @query = query.to_s
          @hints = hints
        end

        def call
          answer_payload = HybridAnswerBuilder.new(
            hotel: hotel,
            query: query,
            intent: "hotel_information",
            topic: "general_hotel_info",
            categories: [ "general_info" ],
            source: "general_hotel_info",
            structured_facts: structured_facts,
            fallback_text: general_fallback_text,
            unavailable_answer: "I couldn't find general hotel information right now.",
            hints: hints
          ).call

          {
            "success" => true,
            "answer" => answer_payload["answer"],
            "answer_mode" => answer_payload["answer_mode"],
            "name" => hotel.name,
            "address" => hotel.address,
            "city" => hotel.city,
            "country" => hotel.country,
            "star_rating" => hotel.star_rating,
            "amenities" => amenity_names,
            "summary_text" => summary_text,
            "source" => "general_hotel_info",
            "knowledge_matches" => answer_payload["knowledge_matches"],
            "searched_categories" => answer_payload["searched_categories"],
            "fallback_categories" => answer_payload["fallback_categories"]
          }
        end

        private

        attr_reader :hotel, :query, :hints

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

        def structured_facts
          {
            "name" => hotel.name,
            "address" => hotel.address,
            "city" => hotel.city,
            "country" => hotel.country,
            "star_rating" => hotel.star_rating,
            "amenities" => amenity_names,
            "summary_text" => summary_text
          }
        end

        def general_fallback_text
          [ summary_text, amenity_names.presence && "Hotel amenities: #{amenity_names.join(', ')}" ].compact.join("\n").presence
        end
      end
    end
  end
end
