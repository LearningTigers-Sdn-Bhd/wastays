module AiConciergeV3
  module Tools
    module RoomInformation
      class GetRoomTypeDetailsTool
        def initialize(hotel:, query:, room_type_name: nil)
          @hotel = hotel
          @query = query.to_s
          @room_type_name = room_type_name
        end

        def call
          match = RoomTypeMatcher.new(room_types: hotel.room_types, query: query, hinted_room_type_name: room_type_name).call
          return match unless match["success"]

          room_type = match.fetch("room_type")

          {
            "success" => true,
            "matched_room_type_id" => room_type.id,
            "room_type_name" => room_type.name,
            "description" => room_type.description,
            "max_adults" => room_type.max_adults,
            "max_children" => room_type.max_children,
            "amenities" => amenity_names_for(room_type)
          }
        end

        private

        attr_reader :hotel, :query, :room_type_name

        def amenity_names_for(room_type)
          lookup = Hotel::ROOM_AMENITIES.index_by { |amenity| amenity[:id] }

          Array(room_type.amenities).filter_map do |amenity_id|
            lookup[amenity_id]&.fetch(:name)
          end
        end
      end
    end
  end
end
