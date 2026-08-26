module AiConcierge
  module Orchestration
    module HotelKnowledge
      class StateHandler
        def initialize(conversation_state:, interpretation:, message:, pause:, active_branch: nil,
          pending_question: nil, clarification_context: nil)
          @conversation_state = conversation_state
          @interpretation = interpretation
          @message = message.to_s
          @pause = pause
          @active_branch = active_branch
          @pending_question = pending_question
          @clarification_context = clarification_context
        end

        def slots_payload
          manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
          payload = if pause
            booking_payload = manager.activate_booking(
              branch_for_suspension,
              pending_question: manager.booking_pending_question || conversation_state.pending_question
            )
            State::ConversationTaskManager.new(slots_payload: booking_payload).suspend_booking_for_information(
              intent: interpretation["intent"],
              topic: interpretation["topic"],
              pending_question: manager.booking_pending_question || conversation_state.pending_question
            )
          else
            manager.payload
          end

          State::ConversationTaskManager.new(slots_payload: payload).update_information_task(
            intent: interpretation["intent"],
            topic: interpretation["topic"],
            question: message,
            pending_question: pending_question,
            context: clarification_context
          )
        end

        private

        attr_reader :conversation_state, :interpretation, :message, :pause, :active_branch, :pending_question,
          :clarification_context

        def branch_for_suspension
          active_branch.is_a?(Hash) ? active_branch : State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).booking_branch
        end
      end
    end
  end
end
