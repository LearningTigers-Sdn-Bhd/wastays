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

        def booking_response(conversation_state:, active_branch:, reply_type:, pending_question:, extra_context: {}, status: nil,
                             action_name: :default, needs_human_support: false)
          slots_payload = booking_payload(conversation_state, active_branch, pending_question: pending_question, status: status)
          slots_payload = State::ConversationTaskManager.new(slots_payload: slots_payload).clear_optional_sales_offer
          manager = State::ConversationTaskManager.new(slots_payload: slots_payload)
          message_context = {
            branch: active_branch,
            price_exploration: manager.price_exploration?
          }.merge(extra_context)

          Core::DomainResponse.booking(
            slots_payload: slots_payload,
            reply_type: reply_type,
            pending_question: pending_question,
            action_name: resolved_action_name(action_name, manager),
            next_action: booking_next_action(
              slots_payload: slots_payload,
              reply_type: reply_type,
              pending_question: pending_question,
              needs_human_support: needs_human_support
            ),
            needs_human_support: needs_human_support,
            extra_context: message_context
          )
        end

        def booking_next_action(slots_payload:, reply_type:, pending_question:, needs_human_support:)
          manager = State::ConversationTaskManager.new(slots_payload: slots_payload)
          return Sales::NextAction.new("offer_front_desk") if needs_human_support
          return Sales::NextAction.new("offer_alternative_search") if reply_type&.to_sym == :no_options
          return Sales::NextAction.none if manager.price_exploration?

          Sales::NextActionPolicy.new(
            intent: "booking_search",
            outcome: booking_outcome(reply_type, pending_question),
            booking_task: manager.booking_task,
            resumable_booking: false,
            needs_human_support: needs_human_support,
            suppress_offer: false
          ).call
        end

        def resolved_action_name(action_name, manager)
          return action_name unless action_name == :default

          manager.price_exploration? ? nil : "request_quote"
        end

        def booking_outcome(reply_type, pending_question)
          return "no_options" if reply_type&.to_sym == :no_options
          return "booking_progress" if pending_question.present?

          "completed"
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
