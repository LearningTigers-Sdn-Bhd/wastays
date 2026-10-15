module AiConcierge
  module Orchestration
    module HotelKnowledge
      class ToolRouter
        def initialize(hotel:, message:, interpretation:, fact_catalogue: nil)
          @hotel = hotel
          @message = message.to_s
          @interpretation = interpretation
          @fact_catalogue = fact_catalogue
        end

        def call
          case interpretation["intent"]
          when "hotel_policy"
            result = Tools::HotelInformation::GetHotelPolicyTool.new(hotel: hotel, policy_topic: interpretation["topic"], query: message, scope: interpretation["scope"], hints: hints).call
            { reply_type: :hotel_policy, active_topic: "hotel_policy", active_flow: "hotel_policy", result: result }
          when "hotel_information"
            tool_class, reply_type = hotel_information_tool_and_reply_type
            arguments = { hotel: hotel, query: message, scope: interpretation["scope"], hints: hints }
            arguments[:fact_catalogue] = fact_catalogue if tool_class == Tools::HotelInformation::GetGeneralHotelInfoTool
            result = tool_class.new(**arguments).call
            { reply_type: reply_type, active_topic: interpretation["topic"], active_flow: "hotel_information", result: result }
          when "nearby_attractions"
            result = Tools::HotelInformation::GetNearbyAttractionsTool.new(hotel: hotel).call
            { reply_type: :nearby_attractions, active_topic: "nearby_attractions", active_flow: "hotel_information", result: result }
          when "room_information"
            result = Tools::RoomInformation::GetRoomTypeDetailsTool.new(
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

        attr_reader :hotel, :message, :interpretation, :fact_catalogue

        # The interpretation is the one thing already threaded through every
        # layer between the model and the search, so the hints ride along in it
        # rather than adding a parameter to four constructors.
        def hints = @hints ||= Retrieval::QueryHints.from(interpretation["retrieval_hints"])

        def hotel_information_tool_and_reply_type
          structured_fact = hints.fact.presence || Retrieval::QueryHints.fact_for_query(message)
          if structured_fact.in?(Retrieval::QueryHints::GUEST_CONTENT_FACTS)
            return [ Tools::HotelInformation::GetGeneralHotelInfoTool, :general_hotel_info ]
          end

          case interpretation["topic"]
          when "hotel_faq"
            [ Tools::HotelInformation::GetHotelFaqTool, :hotel_faq ]
          else
            [ Tools::HotelInformation::GetGeneralHotelInfoTool, :general_hotel_info ]
          end
        end
      end
    end
  end
end
