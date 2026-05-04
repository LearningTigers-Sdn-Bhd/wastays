module AiConciergeV3
  class ConversationSummaryBuilder
    def initialize(conversation_state:)
      @conversation_state = conversation_state
    end

    def call
      return {} unless conversation_state

      {
        active_topic: conversation_state.active_topic,
        active_flow: conversation_state.active_flow,
        pending_question: conversation_state.pending_question,
        flow_status: conversation_state.flow_status,
        active_branch: conversation_state.slots_payload["active"],
        paused_flows_count: conversation_state.paused_flows.count,
        completed_booking_branches_count: Array(conversation_state.slots_payload["completed_booking_branches"]).count
      }
    end

    private

    attr_reader :conversation_state
  end
end
