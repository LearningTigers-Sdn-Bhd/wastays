module AiConcierge
  module Orchestration
    module HotelKnowledge
      class ToolRouter
        def initialize(hotel:, message:, interpretation:, tool_registry: Tools::ToolRegistry.new)
          @hotel = hotel
          @message = message.to_s
          @interpretation = interpretation
          @tool_registry = tool_registry
        end

        def call
          case interpretation["intent"]
          when "hotel_policy"
            result = tool_registry.fetch("get_hotel_policy").new(hotel: hotel, policy_topic: interpretation["topic"], query: message).call
            { reply_type: :hotel_policy, active_topic: "hotel_policy", active_flow: "hotel_policy", result: result }
          when "hotel_information"
            tool_name, reply_type = hotel_information_tool_and_reply_type
            result = tool_registry.fetch(tool_name).new(hotel: hotel, query: message).call
            { reply_type: reply_type, active_topic: interpretation["topic"], active_flow: "hotel_information", result: result }
          when "nearby_attractions"
            result = tool_registry.fetch("get_nearby_attractions").new(hotel: hotel).call
            { reply_type: :nearby_attractions, active_topic: "nearby_attractions", active_flow: "hotel_information", result: result }
          when "room_information"
            result = tool_registry.fetch("get_room_type_details").new(
              hotel: hotel,
              query: message,
              room_type_name: interpretation.dig("slots", "room_type_name")
            ).call

            { reply_type: RoomReplyResolver.new(result: result).call, active_topic: interpretation["topic"], active_flow: "room_information", result: result }
          else
            { reply_type: nil, active_topic: nil, active_flow: nil, result: {} }
          end
        end

        private

        attr_reader :hotel, :message, :interpretation, :tool_registry

        def hotel_information_tool_and_reply_type
          case interpretation["topic"]
          when "hotel_faq"
            [ "get_hotel_faq", :hotel_faq ]
          else
            [ "get_general_hotel_info", :general_hotel_info ]
          end
        end
      end
    end
  end
end
