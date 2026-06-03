module AiConciergeV3
  module State
    class ConversationSummaryBuilder
    MAX_LAST_ASSISTANT_QUESTION_LENGTH = 500
    MAX_SHOWN_ROOM_GROUPS = 3
    MAX_SHOWN_OPTIONS_PER_GROUP = 3

    def initialize(conversation_state:)
      @conversation_state = conversation_state
    end

    def call
      return {} unless conversation_state
      task_manager = ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
      booking_task = task_manager.booking_task
      booking_branch = task_manager.booking_branch
      information_task = task_manager.information_task

      {
        active_topic: conversation_state.active_topic,
        active_flow: conversation_state.active_flow,
        pending_question: conversation_state.pending_question,
        flow_status: conversation_state.flow_status,
        last_assistant_question: last_assistant_question,
        booking_task: {
          status: booking_task["status"],
          pending_question: booking_task["pending_question"],
          suspended: booking_task["suspended"],
          has_suggested_options: Array(booking_branch["suggested_options"]).present?,
          has_confirmation_candidate: booking_branch["confirmation_candidate"].present?,
          has_selected_option: booking_branch["selected_option"].present?,
          shown_options: shown_options(booking_branch),
          rate_plan_options: rate_plan_options(booking_branch),
          selected_option_summary: selected_option_summary(booking_branch),
          target_month: booking_branch["target_month"],
          target_year: booking_branch["target_year"],
          check_in: booking_branch["check_in"],
          check_out: booking_branch["check_out"],
          nights: booking_branch["nights"],
          days: booking_branch["days"],
          adults: booking_branch["adults"],
          children: booking_branch["children"],
          party_size_total: booking_branch["party_size_total"]
        },
        information_task: {
          status: information_task["status"],
          last_intent: information_task["intent"],
          last_topic: information_task["topic"]
        },
        completed_booking_branches_count: Array(task_manager.payload["completed_booking_branches"]).count
      }
    end

    private

    attr_reader :conversation_state

    def last_assistant_question
      body = conversation_state.prospect.prospect_messages
        .where(direction: "outbound")
        .order(sent_at: :desc, created_at: :desc)
        .limit(1)
        .pick(:body)

      body.to_s.squish.truncate(MAX_LAST_ASSISTANT_QUESTION_LENGTH).presence
    end

    def shown_options(booking_branch)
      Array(booking_branch["suggested_options"]).first(MAX_SHOWN_ROOM_GROUPS).filter_map do |group|
        next unless group.is_a?(Hash)

        {
          room_type_name: group["room_type_name"],
          options: Array(group["options"]).first(MAX_SHOWN_OPTIONS_PER_GROUP).filter_map do |option|
            next unless option.is_a?(Hash)

            {
              position: option["position"],
              selection_id: option["selection_id"],
              check_in: option["check_in"],
              check_out: option["check_out"]
            }.compact
          end
        }.compact
      end
    end

    def rate_plan_options(booking_branch)
      selected = selected_option_for_context(booking_branch)
      Array(selected&.dig("rate_plans")).filter_map do |rate_plan|
        next unless rate_plan.is_a?(Hash)

        rate_plan["name"].presence
      end
    end

    def selected_option_summary(booking_branch)
      selected = selected_option_for_context(booking_branch)
      return nil unless selected.is_a?(Hash)

      {
        room_type_name: selected["room_type_name"],
        check_in: selected["check_in"],
        check_out: selected["check_out"],
        selected_rate_plan_name: selected.dig("selected_rate_plan", "name") || booking_branch["selected_rate_plan_name"]
      }.compact
    end

    def selected_option_for_context(booking_branch)
      booking_branch["selected_option"].presence || booking_branch["confirmation_candidate"].presence
    end
    end
  end
end
