module AiConciergeV3
  module Orchestration
    module Booking
      class RatePlanSelectionHandler
        def initialize(message:)
          @message = message.to_s
        end

        def call(conversation_state:, interpretation:, active_branch:)
          rate_plan_name = interpretation.dig("slots", "rate_plan_name")
          selected_option = active_branch["selected_option"]
          rate_plans = Array(selected_option&.dig("rate_plans"))
          matched = Matching::RatePlanMatcher.new(message: message, rate_plan_name: rate_plan_name, rate_plans: rate_plans).call

          if matched
            active_branch["selected_rate_plan_id"] = matched["rate_plan_id"]
            active_branch["selected_rate_plan_name"] = matched["name"]
            selected_option["selected_rate_plan"] = matched
            active_branch["confirmation_candidate"] = selected_option
            active_branch["pending_selection"] = nil
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

        def booking_response(conversation_state:, active_branch:, reply_type:, pending_question:, extra_context: {}, action_name: "request_quote")
          {
            slots_payload: booking_payload(conversation_state, active_branch, pending_question: pending_question),
            reply_type: reply_type,
            active_topic: "booking_search",
            active_flow: "booking_search",
            pending_question: pending_question,
            action_name: action_name,
            extra_context: extra_context
          }
        end

        def booking_payload(conversation_state, active_branch, pending_question:)
          State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).activate_booking(active_branch, pending_question: pending_question)
        end
      end
    end
  end
end
