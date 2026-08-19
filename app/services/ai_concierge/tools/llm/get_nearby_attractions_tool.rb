# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      class GetNearbyAttractionsTool < BaseTool
        description <<~DESCRIPTION
          List the places near the hotel -- attractions, landmarks, and things
          worth going to see. Use this when the guest asks what is nearby or
          what there is to do around the hotel.
        DESCRIPTION

        def execute
          domain_result = Orchestration::HotelKnowledge::Orchestrator.new(
            hotel: hotel,
            message: context.message,
            interpretation: { "intent" => "nearby_attractions", "topic" => "nearby_attractions" },
            conversation_state: context.conversation_state,
            pause: context.info_interruption_active?,
            active_branch: context.booking_branch
          ).call

          record(domain_result, intent: "nearby_attractions", topic: "nearby_attractions",
                 digest: { answered: true })
        end
      end
    end
  end
end
