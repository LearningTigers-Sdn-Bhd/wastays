module AiConciergeV3
  module Tools
    module RoomInformation
      class GetRoomTypeFaqTool
        def initialize(hotel:, query:, room_type_name: nil)
          @hotel = hotel
          @query = query.to_s
          @room_type_name = room_type_name
        end

        def call
          match = RoomTypeMatcher.new(room_types: hotel.room_types, query: query, hinted_room_type_name: room_type_name).call
          return match unless match["success"]

          room_type = match.fetch("room_type")
          faq_text = room_type.faq.to_s.strip

          {
            "success" => faq_text.present?,
            "room_type_name" => room_type.name,
            "faq_text" => faq_text.presence
          }
        end

        private

        attr_reader :hotel, :query, :room_type_name
      end
    end
  end
end
