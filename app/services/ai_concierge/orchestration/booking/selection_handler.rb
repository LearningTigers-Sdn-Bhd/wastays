module AiConcierge
  module Orchestration
    module Booking
      class SelectionHandler
        def initialize(tool_registry:, message:)
          @tool_registry = tool_registry
          @message = message.to_s
        end

        def resolve_follow_up(interpretation:, active_branch:, pending_question:)
          return interpretation if interpretation.dig("conversation_signals", "end_conversation")
          return interpretation unless pending_question == "select_option"
          return interpretation unless Array(active_branch&.dig("suggested_options")).present?
          return interpretation if informational_intent?(interpretation["intent"])

          result = selection_tool.new(
            option_number: interpretation.dig("slots", "option_number"),
            suggested_options: active_branch["suggested_options"],
            suggestion_set_version: active_branch["suggestion_set_version"],
            message: message
          ).call
          return interpretation unless result["success"]

          resolved_selection_interpretation(interpretation, result)
        end

        def handle_selection(conversation_state:, interpretation:, active_branch:)
          result = selection_tool.new(
            option_number: interpretation.dig("slots", "option_number"),
            suggested_options: active_branch["suggested_options"],
            suggestion_set_version: active_branch["suggestion_set_version"],
            selection_id: interpretation.dig("slots", "selection_id"),
            message: message
          ).call

          unless result["success"]
            return booking_response(
              conversation_state: conversation_state,
              active_branch: active_branch,
              reply_type: :invalid_selection,
              pending_question: "select_option"
            )
          end

          selected_option = result["selected_option"]
          rate_plans = Array(selected_option["rate_plans"])

          # Both lists are answered by position, so a number on this turn is the
          # row of the catalogue and cannot also be a row of the rate list. A
          # room with more than one plan therefore always asks, rather than
          # guessing a rate out of the same message.
          if rate_plans.many?
            active_branch["selected_option"] = selected_option
            return booking_response(
              conversation_state: conversation_state,
              active_branch: active_branch,
              reply_type: :ask_rate_plan,
              pending_question: "rate_plan_selection",
              extra_context: { selected_option: selected_option, rate_plans: rate_plans }
            )
          end

          selected_option["selected_rate_plan"] = rate_plans.first if rate_plans.any?
          active_branch["confirmation_candidate"] = selected_option
          active_branch["selected_option"] = selected_option
          booking_response(
            conversation_state: conversation_state,
            active_branch: active_branch,
            reply_type: :ask_confirmation,
            pending_question: "confirm_selection",
            extra_context: { selected_option: selected_option }
          )
        end

        private

        attr_reader :tool_registry, :message

        def selection_tool
          tool_registry.fetch("select_booking_option")
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

        def resolved_selection_interpretation(interpretation, result)
          interpretation.deep_dup.tap do |value|
            value["intent"] = "option_selection"
            value["slots"] = value.fetch("slots", {}).merge("selection_id" => result.dig("selected_option", "selection_id"))
          end
        end

        def informational_intent?(intent)
          %w[hotel_policy hotel_information nearby_attractions room_information booking_context].include?(intent.to_s)
        end
      end
    end
  end
end
