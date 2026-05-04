module AiConciergeV3
  class BranchManager
    def initialize(slots_payload:, now: Time.current)
      @payload = normalize_payload(slots_payload)
      @now = now
    end

    def start_branch(branch)
      payload.merge("active" => branch, "paused_flows" => payload["paused_flows"], "completed_booking_branches" => payload["completed_booking_branches"])
    end

    def pause_active(topic:, pending_question:)
      active = payload["active"]
      return payload unless active.is_a?(Hash) && active.present?

      paused_flow = {
        "topic" => topic,
        "flow" => topic,
        "pending_question" => pending_question,
        "slots" => active,
        "updated_at" => now.iso8601,
        "expires_at" => (now + ProspectConversationState::PAUSED_FLOW_TTL).iso8601
      }

      payload.merge(
        "active" => nil,
        "paused_flows" => [ paused_flow ] + payload["paused_flows"]
      )
    end

    def resume_latest(topic: "booking_search")
      flow = latest_resumable_flow(topic: topic)
      return [ payload, nil ] unless flow

      remaining = payload["paused_flows"].reject { |candidate| candidate == flow }
      resumed_payload = payload.merge("active" => flow["slots"], "paused_flows" => remaining)

      [ resumed_payload, flow ]
    end

    def archive_completed_active
      active = payload["active"]
      return payload unless active.is_a?(Hash) && active.present?

      completed = payload["completed_booking_branches"] + [
        {
          "branch_id" => active["branch_id"],
          "selected_option" => active["selected_option"],
          "completed_at" => now.iso8601
        }
      ]

      payload.merge("active" => nil, "completed_booking_branches" => completed.last(5))
    end

    private

    attr_reader :payload, :now

    def latest_resumable_flow(topic:)
      payload["paused_flows"]
        .select { |flow| flow.is_a?(Hash) && flow["topic"] == topic }
        .reject { |flow| expired?(flow) }
        .max_by { |flow| Time.zone.parse(flow["updated_at"].to_s) || Time.at(0) }
    end

    def expired?(flow)
      expires_at = Time.zone.parse(flow["expires_at"].to_s)
      expires_at.present? && expires_at <= now
    rescue ArgumentError
      false
    end

    def normalize_payload(value)
      hash = value.is_a?(Hash) ? value.deep_dup : {}
      hash["paused_flows"] = Array(hash["paused_flows"]).select { |entry| entry.is_a?(Hash) }
      hash["completed_booking_branches"] = Array(hash["completed_booking_branches"]).select { |entry| entry.is_a?(Hash) }
      hash
    end
  end
end
