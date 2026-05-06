module AiConciergeV3
  module State
    class StatePatchBuilder
    def initialize(conversation_state:, slots_payload:, active_topic:, active_flow:, pending_question:, last_intent:, last_action_name:, flow_status: "active", end_reason: nil, now: Time.current)
      @conversation_state = conversation_state
      @slots_payload = slots_payload
      @active_topic = active_topic
      @active_flow = active_flow
      @pending_question = pending_question
      @last_intent = last_intent
      @last_action_name = last_action_name
      @flow_status = flow_status
      @end_reason = end_reason
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
        last_user_message_at: now,
        slots_payload: normalized_slots_payload
      }
    end

    private

    attr_reader :conversation_state, :slots_payload, :active_topic, :active_flow, :pending_question, :last_intent, :last_action_name, :flow_status, :end_reason, :now

    def normalized_slots_payload
      payload = slots_payload.is_a?(Hash) ? slots_payload.deep_dup : {}
      payload["paused_flows"] = Array(payload["paused_flows"])
      payload["completed_booking_branches"] = Array(payload["completed_booking_branches"])
      payload["conversation"] = conversation_payload(payload["conversation"])
      payload
    end

    def conversation_payload(existing)
      conversation = existing.is_a?(Hash) ? existing.deep_dup : {}
      conversation["started_at"] ||= conversation_state&.created_at&.iso8601 || now.iso8601
      conversation["last_user_message_at"] = now.iso8601
      conversation["turn_count"] = conversation["turn_count"].to_i + 1

      if flow_status == "ended"
        conversation["status"] = "ended"
        conversation["ended_at"] = now.iso8601
        conversation["end_reason"] = end_reason.presence || "ended"
      else
        conversation["status"] = "active"
        conversation["ended_at"] = nil
        conversation["end_reason"] = nil
      end

      conversation
    end
    end
  end
end
