# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      class GetNearbyAttractionsFunction < BaseFunction
        description <<~DESCRIPTION
          List the places near the hotel -- attractions, landmarks, and things
          worth going to see. Use this when the guest asks what is nearby or
          what there is to do around the hotel.
        DESCRIPTION

        param :guest_language, type: "string", required: false,
          desc: "ISO 639-1 code for the language used in the guest's message."

        def execute(guest_language: nil)
          domain_result = Orchestration::HotelKnowledge::Orchestrator.new(
            hotel: hotel,
            message: context.message,
            interpretation: { "intent" => "nearby_attractions", "topic" => "nearby_attractions" },
            conversation_state: context.conversation_state,
            pause: context.info_interruption_active?,
            active_branch: context.booking_branch,
            language: guest_language.presence || context.thread_language,
            guest_language: guest_language
          ).call

          record(domain_result, digest: { answered: true })
        end
      end
    end
  end
end
