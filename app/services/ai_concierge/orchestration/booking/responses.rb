# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Booking
      # How every exit of the booking ladder answers a turn.
      #
      # This was four copies -- `Orchestrator`, `SelectionHandler`,
      # `RatePlanSelectionHandler`, `CompletionHandler` -- and they had drifted
      # on the one argument that matters: `count_reask`. Three passed it,
      # `CompletionHandler` did not, so Phase I's escape hatch (nudge on the
      # second ask, ask for a person on the third) could not fire from the
      # class that owns the confirmation. Whether that produced a stuck thread
      # in practice was not answerable by reading four copies, which is why
      # there is one now.
      module Responses
        private

        def booking_response(conversation_state:, active_branch:, reply_type:, pending_question:, extra_context: {}, status: nil, action_name: "request_quote")
          Core::DomainResponse.booking(
            slots_payload: booking_payload(conversation_state, active_branch, pending_question: pending_question, status: status),
            reply_type: reply_type,
            pending_question: pending_question,
            action_name: action_name,
            extra_context: extra_context
          )
        end

        # `count_reask: true` everywhere a reply is written. The bookkeeping
        # callers that must *not* count -- PrepareTurn, the knowledge
        # interruption, a resume -- do not come through here; they call
        # `activate_booking` directly, which is what makes counting the default
        # safe to state in one place.
        def booking_payload(conversation_state, active_branch, pending_question:, status: nil)
          State::ConversationTaskManager
            .new(slots_payload: conversation_state.slots_payload)
            .activate_booking(active_branch, pending_question: pending_question, status: status, count_reask: true)
        end
      end
    end
  end
end
