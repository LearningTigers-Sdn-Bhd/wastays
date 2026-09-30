# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Turn
      class EscalationHandler
        def initialize(hotel:, conversation:, message:)
          @hotel = hotel
          @conversation = conversation
          @message = message.to_s
        end

        def call(conversation_state:)
          trigger = Matching::EscalationMatcher.new(message: message).call
          return unless trigger

          decision = Escalation::Policy.new(hotel: hotel, conversation: conversation, trigger: trigger).call
          return unless decision.handoff?

          Core::DomainResponse.new(
            slots_payload: conversation_state.slots_payload,
            next_action: Sales::NextAction.new("offer_front_desk"),
            needs_human_support: true,
            extra_context: { message: decision.message, escalation_trigger: trigger }
          )
        end

        private

        attr_reader :hotel, :conversation, :message
      end
    end
  end
end
