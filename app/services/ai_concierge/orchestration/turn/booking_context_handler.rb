module AiConcierge
  module Orchestration
    module Turn
      class BookingContextHandler
        def initialize(hotel:, phone:, tool_registry: Tools::ToolRegistry.new)
          @hotel = hotel
          @phone = phone.to_s.presence
          @tool_registry = tool_registry
        end

        def call(prospect:, conversation_state:)
          result = tool_registry.fetch("get_booking_context").new(hotel: hotel, phone: phone || prospect.phone_number).call

          Core::DomainResponse.new(
            slots_payload: conversation_state.slots_payload,
            reply_type: :booking_context,
            extra_context: result.symbolize_keys
          )
        end

        private

        attr_reader :hotel, :phone, :tool_registry
      end
    end
  end
end
