# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # What the loop hands back to the persister.
      #
      # A conversation state and the keys ResponsePersister reads off a domain
      # result -- nothing else. It carried an intent and a topic too, for two
      # columns that were written and never read; both went with the
      # interpreting pipeline that named them.
      Outcome = Struct.new(:conversation_state, :domain_result, keyword_init: true) do
        def self.fallback(conversation_state:, message: nil)
          new(
            conversation_state: conversation_state,
            domain_result: Core::DomainResponse.new(
              slots_payload: conversation_state.slots_payload,
              extra_context: { message: message.presence || MessageBuilders::DEFAULT_MESSAGE }
            )
          )
        end
      end
    end
  end
end
