# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Turn
      # Keeps an idle greeting out of the tool loop and out of the booking ladder.
      class GreetingHandler
        IDLE_BOOKING_STATUSES = %w[idle expired].freeze

        def initialize(message:)
          @message = message.to_s
        end

        def call(conversation_state:)
          return unless Matching::GreetingMatcher.new(message: message).standalone?
          return unless idle?(conversation_state)

          manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
          Core::DomainResponse.new(
            slots_payload: manager.show_suggestions("greeting"),
            reply_type: :greeting,
            next_action: Sales::NextAction.none
          )
        end

        private

        attr_reader :message

        def idle?(conversation_state)
          manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)

          IDLE_BOOKING_STATUSES.include?(manager.booking_task["status"]) &&
            manager.information_task["pending_question"].blank? &&
            conversation_state.pending_question.blank?
        end
      end
    end
  end
end
