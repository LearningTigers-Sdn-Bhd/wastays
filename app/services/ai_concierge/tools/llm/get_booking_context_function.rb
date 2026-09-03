# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      class GetBookingContextFunction < BaseFunction
        description <<~DESCRIPTION
          Look up the booking this guest already has with the hotel -- their
          dates and room. Use this when they ask about "my booking", "my
          reservation" or "my stay", not when they are trying to make a new one.
        DESCRIPTION

        def execute
          domain_result = Orchestration::Turn::BookingContextHandler.new(
            hotel: hotel,
            phone: context.phone,
            conversation: context.conversation
          ).call(prospect: context.prospect, conversation_state: context.conversation_state)

          record(domain_result, digest: { answered: true })
        end
      end
    end
  end
end
