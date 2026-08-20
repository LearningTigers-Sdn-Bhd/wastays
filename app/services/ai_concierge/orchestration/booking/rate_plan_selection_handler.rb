module AiConcierge
  module Orchestration
    module Booking
      class RatePlanSelectionHandler
        def initialize(message:)
          @message = message.to_s
        end

        # Nil when there is no room left to price.
        #
        # The rate question is written from the chosen option, so an option
        # that has gone -- cleared by a slot change the turn before -- renders
        # as a room with no name, a stay with no dates and a list with no rates
        # on it. Asking again is only an answer while there is something to
        # choose between; the caller decides what to say when there is not.
        def call(conversation_state:, active_branch:)
          selected_option = active_branch["selected_option"]
          rate_plans = Array(selected_option&.dig("rate_plans"))
          return if rate_plans.empty?

          matched = matched_rate_plan(rate_plans)

          if matched
            ApplyRatePlan.new(active_branch: active_branch, selected_option: selected_option, rate_plan: matched).call
            return booking_response(
              conversation_state: conversation_state,
              active_branch: active_branch,
              reply_type: :ask_confirmation,
              pending_question: "confirm_selection",
              extra_context: { selected_option: selected_option }
            )
          end

          booking_response(
            conversation_state: conversation_state,
            active_branch: active_branch,
            reply_type: :ask_rate_plan,
            pending_question: "rate_plan_selection",
            extra_context: { selected_option: selected_option, rate_plans: rate_plans }
          )
        end

        private

        attr_reader :message

        # The rate list is numbered the same way the catalogue is, and is read
        # the same way: by the row the guest named. A rate plan's name is not a
        # second way in -- guessing at one only ever priced a stay the guest had
        # not asked about.
        def matched_rate_plan(rate_plans)
          return rate_plans.first if rate_plans.one?

          position = Matching::OptionReference.new(message: message).number.to_i
          rate_plans[position - 1] if position.positive?
        end

        def booking_response(conversation_state:, active_branch:, reply_type:, pending_question:, extra_context: {}, action_name: "request_quote")
          Core::DomainResponse.booking(
            slots_payload: booking_payload(conversation_state, active_branch, pending_question: pending_question),
            reply_type: reply_type,
            pending_question: pending_question,
            action_name: action_name,
            extra_context: extra_context
          )
        end

        def booking_payload(conversation_state, active_branch, pending_question:)
          State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).activate_booking(active_branch, pending_question: pending_question, count_reask: true)
        end
      end
    end
  end
end
