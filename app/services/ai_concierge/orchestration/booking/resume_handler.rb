module AiConcierge
  module Orchestration
    module Booking
      class ResumeHandler
        def initialize(conversation_state:, interpretation:, active_branch:, message:, selection_handler:, completion_handler:, action_resolver:, process_booking_action:, handle_booking_revision:, handle_search_options:, domain_response:)
          @conversation_state = conversation_state
          @interpretation = interpretation
          @active_branch = active_branch
          @message = message.to_s
          @selection_handler = selection_handler
          @completion_handler = completion_handler
          @action_resolver = action_resolver
          @process_booking_action = process_booking_action
          @handle_booking_revision = handle_booking_revision
          @handle_search_options = handle_search_options
          @domain_response = domain_response
        end

        def call
          slots_payload, resumed = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).resume_booking
          branch = resumed&.dig("branch") || empty_branch
          resumed_state = temporary_state(conversation_state, slots_payload)

          revision_response = handle_booking_revision.call(conversation_state: resumed_state, active_branch: branch)
          return revision_response if revision_response

          if resumed&.dig("pending_question") == "confirm_selection" && interpretation["intent"] == "confirmation"
            if interpretation.dig("slots", "confirmation") == "no"
              branch["confirmation_candidate"] = nil
              return booking_response(
                conversation_state: resumed_state,
                active_branch: branch,
                reply_type: :suggest_options,
                pending_question: "select_option",
                extra_context: {
                  options: branch["suggested_options"],
                  month_label: month_label(branch),
                  guest_label: guest_label(branch)
                }
              )
            end

            return completion_handler.call(conversation_state: resumed_state, active_branch: branch)
          end

          if slot_collection_resume?(resumed)
            return process_booking_action.call(action_resolver.call, conversation_state: resumed_state, active_branch: active_branch)
          end

          if selection_like_resume_message?(interpretation, branch)
            resolved_interpretation = selection_handler.resolve_follow_up(
              conversation_state: resumed_state,
              interpretation: interpretation,
              active_branch: branch,
              pending_question: "select_option"
            )
            return resolved_interpretation if domain_response?(resolved_interpretation)

            resume_slots = if resolved_interpretation.dig("slots", "selection_id").present?
              { "selection_id" => resolved_interpretation.dig("slots", "selection_id") }
            else
              resolved_interpretation["slots"]
            end

            branch = State::SlotMerger.new(
              active_branch: branch,
              slots: resume_slots,
              pending_question: resumed&.dig("pending_question"),
              message: message
            ).call
            return selection_handler.handle_selection(conversation_state: resumed_state, interpretation: resolved_interpretation, active_branch: branch)
          end

          if branch["suggested_options"].present?
            search_params = search_params_for(branch)
            return domain_response.call(
              slots_payload: slots_payload,
              reply_type: :resume_options,
              active_topic: "booking_search",
              active_flow: "booking_search",
              pending_question: "select_option",
              action_name: "request_quote",
              extra_context: {
                options: branch["suggested_options"],
                month_label: month_label(branch),
                guest_label: guest_label(branch),
                search_params: search_params
              }
            )
          end

          return handle_search_options.call(conversation_state: resumed_state, active_branch: branch) if resumed

          domain_response.call(slots_payload: conversation_state.slots_payload, reply_type: :ask_booking_timing)
        end

        private

        attr_reader :conversation_state, :interpretation, :active_branch, :message, :selection_handler,
          :completion_handler, :action_resolver, :process_booking_action, :handle_booking_revision,
          :handle_search_options, :domain_response

        def booking_response(conversation_state:, active_branch:, reply_type:, pending_question:, extra_context: {}, action_name: "request_quote")
          domain_response.call(
            slots_payload: booking_payload(conversation_state, active_branch, pending_question: pending_question),
            reply_type: reply_type,
            active_topic: "booking_search",
            active_flow: "booking_search",
            pending_question: pending_question,
            action_name: action_name,
            extra_context: extra_context
          )
        end

        def booking_payload(conversation_state, active_branch, pending_question:, status: nil)
          State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).activate_booking(active_branch, pending_question: pending_question, status: status)
        end

        def temporary_state(conversation_state, slots_payload)
          conversation_state.tap { |state| state.assign_attributes(slots_payload: slots_payload) }
        end

        def month_label(branch)
          month = branch["target_month"]
          year = branch["target_year"]
          return if month.blank? || year.blank?

          [ branch["month_segment"].presence, Date::MONTHNAMES[month.to_i], year ].compact.join(" ")
        end

        def guest_label(branch)
          adults = branch["adults"].to_i
          children = branch["children"].to_i
          parts = []
          parts << "#{adults} adult#{'s' unless adults == 1}" if adults.positive?
          parts << "#{children} child#{'ren' unless children == 1}" if children.positive?
          parts.join(" and ").presence
        end

        def search_params_for(branch, options: branch["suggested_options"])
          search_params = branch.slice("check_in", "check_out", "adults", "children", "room_count")
          if search_params["check_in"].blank? && Array(options).present?
            first_opt = options.first["options"].first
            search_params["check_in"] = first_opt["check_in"]
            search_params["check_out"] = first_opt["check_out"]
          end
          search_params
        end

        def selection_like_resume_message?(interpretation, active_branch)
          return true if interpretation["intent"] == "option_selection"
          return true if interpretation.dig("slots", "check_in").present?
          return true if interpretation.dig("slots", "option_number").present?

          room_type_names = Array(active_branch["suggested_options"]).filter_map { |group| group["room_type_name"] if group.is_a?(Hash) }
          normalized_message = message.downcase.gsub(/[^a-z0-9]+/, " ").squish

          room_type_names.any? do |name|
            name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish.split.any? do |token|
              token.length > 2 && normalized_message.include?(token)
            end
          end
        end

        def slot_collection_resume?(resumed)
          %w[booking_timing specific_timing duration guest_count party_split rate_plan_selection].include?(resumed&.dig("pending_question"))
        end

        def domain_response?(value)
          value.is_a?(Hash) && value.key?(:slots_payload) && value.key?(:reply_type)
        end

        def empty_branch
          State::SlotMerger.empty_branch
        end
      end
    end
  end
end
