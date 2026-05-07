module AiConciergeV3
  module State
    class ConversationSummaryBuilder
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
        booking_task: {
          status: booking_task["status"],
          pending_question: booking_task["pending_question"],
          suspended: booking_task["suspended"],
          has_suggested_options: Array(booking_branch["suggested_options"]).present?,
          has_confirmation_candidate: booking_branch["confirmation_candidate"].present?,
          has_selected_option: booking_branch["selected_option"].present?,
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
    end
  end
end
