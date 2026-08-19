# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module AgentLoop
      # What the loop hands back to the persister.
      #
      # ResponsePersister reads nine keys off a domain result plus
      # `interpretation["intent"]`, so producing both leaves it, MessengerAgent,
      # the outbound message row, the Turbo broadcast and the WhatsApp relay
      # untouched by this rewrite. The rewrite is meant to change how the
      # concierge decides, not how a reply reaches a guest.
      Outcome = Struct.new(:conversation_state, :domain_result, :intent, :topic, keyword_init: true) do
        # The persister and StatePatchBuilder still speak "interpretation".
        # This is the last of that vocabulary, and it is two keys wide.
        def interpretation = { "intent" => intent, "topic" => topic }

        def self.fallback(conversation_state:, message: nil)
          new(
            conversation_state: conversation_state,
            intent: "fallback",
            domain_result: {
              slots_payload: conversation_state.slots_payload,
              reply_type: nil,
              active_topic: nil,
              active_flow: nil,
              pending_question: nil,
              action_name: nil,
              extra_context: { message: message.presence || MessageBuilders::FallbackBuilder::DEFAULT_MESSAGE }
            }
          )
        end
      end
    end
  end
end
