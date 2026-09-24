module AiConcierge
  module Tools
    module HotelInformation
      class GetGeneralHotelInfoTool
        def initialize(hotel:, query: nil, scope: nil, hints: Retrieval::QueryHints.none)
          @hotel = hotel
          @query = query.to_s
          @hints = hints
          @scope = scope
        end

        def call
          reply = HybridAnswerBuilder.new(
            hotel: hotel,
            query: query,
            intent: "hotel_information",
            topic: "general_hotel_info",
            categories: [ "general_info" ],
            source: "general_hotel_info",
            structured_facts: structured_facts,
            fallback_text: general_fallback_text,
            scope: scope,
            hints: hints
          ).call

          reply.to_h.merge(
            "name" => hotel.name,
            "address" => hotel.address,
            "city" => hotel.city,
            "country" => hotel.country,
            "star_rating" => hotel.star_rating,
            "description" => hotel.description.presence,
            "amenities" => amenity_names,
            "amenity_details" => amenity_details,
            "wifi_available" => guest_wifi_available?,
            "summary_text" => summary_text
          )
        end

        private

        attr_reader :hotel, :query, :scope, :hints

        def summary_text
          parts = [ hotel.name ]
          parts << "is a #{hotel.star_rating}-star hotel" if hotel.star_rating.present?

          location = [ hotel.address, hotel.city, hotel.country ].compact_blank.join(", ")
          parts << "located at #{location}" if location.present?

          # The description from Property Settings is the property's own
          # summary, the same text the concierge Property Info page shows.
          [ "#{parts.join(' ')}.", hotel.description.presence ].compact.join(" ")
        end

        def amenity_names
          lookup = Hotel::HOTEL_AMENITIES.index_by { |amenity| amenity[:id] }

          Array(hotel.amenities).filter_map do |amenity_id|
            lookup[amenity_id]&.fetch(:name)
          end
        end

        def amenity_details
          hotel.hotel_amenity_details.includes(:amenity).filter_map do |detail|
            next unless detail.available?

            {
              "slug" => detail.amenity.slug,
              "name" => detail.amenity.name,
              "location" => detail.location,
              "opening_hours" => detail.opening_hours,
              "fee_information" => detail.fee_information,
              "reservation_required" => detail.reservation_required,
              "reservation_instructions" => detail.reservation_instructions,
              "guest_notes" => detail.guest_notes
            }.compact_blank
          end
        end

        def guest_wifi_available?
          hotel.hotel_wifi_networks.for_guest.exists?
        end

        def structured_facts
          {
            "name" => hotel.name,
            "address" => hotel.address,
            "city" => hotel.city,
            "country" => hotel.country,
            "star_rating" => hotel.star_rating,
            "description" => hotel.description.presence,
            "amenities" => amenity_names,
            "amenity_details" => amenity_details,
            "wifi_available" => guest_wifi_available?,
            "summary_text" => summary_text
          }
        end

        def general_fallback_text
          facts = []
          facts << "The hotel has a #{hotel.star_rating}-star rating." if hotel.star_rating.present?

          location = [ hotel.address, hotel.city, hotel.country ].compact_blank.join(", ")
          facts << "The hotel is located at #{location}." if location.present?
          facts << hotel.description if hotel.description.present?
          facts << "Available amenities include #{amenity_names.to_sentence}." if amenity_names.present?
          facts.join(" ").presence
        end
      end
    end
  end
end
