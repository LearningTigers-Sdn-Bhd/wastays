# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Turn
      class SecureInputHandler
        def initialize(conversation: nil)
          @conversation = conversation
        end

        def call(conversation_state:)
          manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
          confirmation_code_response(conversation_state) if manager.existing_booking_pending?(
            conversation_id: conversation&.id
          )
        end

        private

        attr_reader :conversation

        def confirmation_code_response(conversation_state)
          Core::DomainResponse.new(
            slots_payload: conversation_state.slots_payload,
            reply_type: :ask_existing_booking_confirmation_code,
            active_topic: "existing_booking",
            active_flow: "existing_booking",
            pending_question: "confirmation_code"
          )
        end
      end
    end
  end
end
