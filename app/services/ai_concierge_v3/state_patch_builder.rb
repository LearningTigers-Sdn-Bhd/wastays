module AiConciergeV3
  class StatePatchBuilder
    def initialize(conversation_state:, slots_payload:, active_topic:, active_flow:, pending_question:, last_intent:, last_action_name:, flow_status: "active", now: Time.current)
      @conversation_state = conversation_state
      @slots_payload = slots_payload
      @active_topic = active_topic
      @active_flow = active_flow
      @pending_question = pending_question
      @last_intent = last_intent
      @last_action_name = last_action_name
      @flow_status = flow_status
      @now = now
    end

    def call
      {
        active_topic: active_topic,
        active_flow: active_flow,
        pending_question: pending_question,
        last_intent: last_intent,
        last_action_name: last_action_name,
        flow_status: flow_status,
        last_user_message_at: conversation_state&.last_user_message_at || now,
        slots_payload: normalized_slots_payload
      }
    end

    private

    attr_reader :conversation_state, :slots_payload, :active_topic, :active_flow, :pending_question, :last_intent, :last_action_name, :flow_status, :now

    def normalized_slots_payload
      payload = slots_payload.is_a?(Hash) ? slots_payload.deep_dup : {}
      payload["paused_flows"] = Array(payload["paused_flows"])
      payload["completed_booking_branches"] = Array(payload["completed_booking_branches"])
      payload
    end
  end
end
