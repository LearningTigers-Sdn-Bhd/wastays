module AiConcierge
  module Orchestration
    module Booking
      class SelectionHandler
        def initialize(tool_registry:, message:)
          @tool_registry = tool_registry
          @message = message.to_s
        end

        def resolve_follow_up(conversation_state:, interpretation:, active_branch:, pending_question:)
          return interpretation if interpretation.dig("conversation_signals", "end_conversation")
          return interpretation unless pending_question == "select_option"
          return interpretation unless Array(active_branch&.dig("suggested_options")).present?
          return interpretation if informational_intent?(interpretation["intent"])

          branch = active_branch.deep_dup
          result = selection_tool.new(
            option_number: interpretation.dig("slots", "option_number"),
            suggested_options: branch["suggested_options"],
            suggestion_set_version: branch["suggestion_set_version"],
            check_in: interpretation.dig("slots", "check_in"),
            message: message,
            pending_selection: branch["pending_selection"]
          ).call

          return resolved_selection_interpretation(interpretation, result) if result["success"]
          return interpretation unless selection_error_reply_type(result)

          branch["pending_selection"] = pending_selection_for(result)
          booking_response(
            conversation_state: conversation_state,
            active_branch: branch,
            reply_type: selection_error_reply_type(result),
            pending_question: "select_option",
            extra_context: selection_error_context(result, branch)
          )
        end

        def handle_selection(conversation_state:, interpretation:, active_branch:)
          result = selection_tool.new(
            option_number: interpretation.dig("slots", "option_number"),
            suggested_options: active_branch["suggested_options"],
            suggestion_set_version: active_branch["suggestion_set_version"],
            selection_id: interpretation.dig("slots", "selection_id"),
            check_in: interpretation.dig("slots", "check_in"),
            message: message,
            pending_selection: active_branch["pending_selection"]
          ).call

          if result["success"]
            selected_option = result["selected_option"]
            rate_plans = Array(selected_option["rate_plans"])

            if rate_plans.size > 1
              same_turn_rate_plan = same_turn_rate_plan(interpretation, selected_option, rate_plans)

              if same_turn_rate_plan
                ApplyRatePlan.new(active_branch: active_branch, selected_option: selected_option, rate_plan: same_turn_rate_plan).call
                return booking_response(
                  conversation_state: conversation_state,
                  active_branch: active_branch,
                  reply_type: :ask_confirmation,
                  pending_question: "confirm_selection",
                  extra_context: { selected_option: selected_option }
                )
              end

              active_branch["selected_option"] = selected_option
              active_branch["pending_selection"] = nil
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
            active_branch["pending_selection"] = nil
            return booking_response(
              conversation_state: conversation_state,
              active_branch: active_branch,
              reply_type: :ask_confirmation,
              pending_question: "confirm_selection",
              extra_context: { selected_option: result["selected_option"] }
            )
          end

          active_branch["pending_selection"] = pending_selection_for(result)
          booking_response(
            conversation_state: conversation_state,
            active_branch: active_branch,
            reply_type: selection_error_reply_type(result) || :invalid_selection,
            pending_question: "select_option",
            extra_context: selection_error_context(result, active_branch)
          )
        end

        private

        attr_reader :tool_registry, :message

        # "Garden Prestige, standard rate" names a room and a rate plan in one
        # breath, and answering only the first half asks the guest to repeat
        # the second.
        #
        # The message is only safe to read for the rate plan when it carries no
        # option ordinal: RatePlanMatcher reads a bare "1" as the first rate
        # plan, so "Ocean Villa King option 1" would otherwise pick a rate plan
        # the guest never mentioned. With an ordinal on the turn, only the
        # model's own rate_plan_name is trusted.
        def same_turn_rate_plan(interpretation, selected_option, rate_plans)
          rate_plan_name = interpretation.dig("slots", "rate_plan_name")
          readable_message = option_ordinal_on_turn?(interpretation) ? "" : message_without_room_name(selected_option)
          return if rate_plan_name.blank? && readable_message.blank?

          Matching::RatePlanMatcher.new(
            message: readable_message,
            rate_plan_name: rate_plan_name,
            rate_plans: rate_plans
          ).call
        end

        # The room's own name is not evidence about a rate plan. Left in, a
        # "Standard Room" would select the "Standard Rate" the guest never
        # asked for.
        def message_without_room_name(selected_option)
          normalized = message.downcase.gsub(/[^a-z0-9]+/, " ").squish
          room_tokens = selected_option["room_type_name"].to_s.downcase.gsub(/[^a-z0-9]+/, " ").split

          (normalized.split - room_tokens).join(" ")
        end

        def option_ordinal_on_turn?(interpretation)
          return true if interpretation.dig("slots", "option_number").present?

          normalized = message.downcase.gsub(/[^a-z0-9]+/, " ").squish
          normalized.match?(/\b(?:option|number|choice)\s*\d+\b/) ||
            normalized.match?(/\b(?:choose|chose|picked|pick|take|go with)\s+(?:option\s*)?\d+\b/)
        end

        def selection_tool
          tool_registry.fetch("select_booking_option")
        end

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

        def selection_error_reply_type(result)
          case result["error"]
          when "room_type_requires_option_number"
            :room_type_requires_option_number
          when "ambiguous_option_selection"
            :ambiguous_option_selection
          when "ambiguous_date_selection"
            :ambiguous_date_selection
          end
        end

        def selection_error_context(result, branch)
          case result["error"]
          when "room_type_requires_option_number"
            { room_type_name: result["room_type_name"], room_options: room_options_for(branch, result["room_type_name"]) }
          when "ambiguous_option_selection"
            { room_type_names: result["room_type_names"], option_number: result["option_number"] }
          when "ambiguous_date_selection"
            { room_type_names: result["room_type_names"], check_in: result["check_in"] }
          else
            {}
          end
        end

        def pending_selection_for(result)
          case result["error"]
          when "room_type_requires_option_number"
            { "room_type_name" => result["room_type_name"], "check_in" => result["check_in"] }.compact
          when "ambiguous_date_selection"
            { "check_in" => result["check_in"], "candidate_room_type_names" => result["room_type_names"] }
          else
            nil
          end
        end

        def resolved_selection_interpretation(interpretation, result)
          interpretation.deep_dup.tap do |value|
            value["intent"] = "option_selection"
            value["slots"] = value.fetch("slots", {}).merge("selection_id" => result.dig("selected_option", "selection_id"))
          end
        end

        def room_options_for(branch, room_type_name)
          Array(branch["suggested_options"]).find { |group| group.is_a?(Hash) && group["room_type_name"] == room_type_name }
        end

        def informational_intent?(intent)
          %w[hotel_policy hotel_information nearby_attractions room_information booking_context].include?(intent.to_s)
        end
      end
    end
  end
end
