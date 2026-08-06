module AiConcierge
  module Orchestration
    module HotelKnowledge
      class RoomReplyResolver
        def initialize(result:)
          @result = result
        end

        def call
          if result["success"]
            :room_type_details
          elsif result["error"] == "ambiguous_room_type"
            :ambiguous_room_type
          else
            :room_type_not_found
          end
        end

        private

        attr_reader :result
      end
    end
  end
end
