module AiConcierge
  module State
    class ConversationTaskManager
    STATE_VERSION = 2
    SUSPENDED_BOOKING_TTL = ProspectConversationState::PAUSED_FLOW_TTL

    def initialize(slots_payload:, now: Time.current)
      @payload = normalize_payload(slots_payload)
      @now = now
    end

    attr_reader :payload

    def booking_task
      payload["booking_task"]
    end

    def information_task
      payload["information_task"]
    end

    def booking_branch
      branch = booking_task["branch"]
      branch.is_a?(Hash) ? branch : default_branch
    end

    def booking_pending_question
      booking_task["pending_question"].presence
    end

    def suspended_booking?
      booking_task["status"] == "suspended" || booking_task["suspended"] == true
    end

    def suspended_booking_resumable?
      suspended_booking? && !expired?(booking_task)
    end

    def activate_booking(branch, pending_question:, status: nil)
      update_booking_task(
        "status" => status.presence || status_for_pending_question(pending_question),
        "pending_question" => pending_question,
        "branch" => normalize_branch(branch),
        "suspended" => false,
        "suspended_at" => nil,
        "expires_at" => nil
      )
    end

    def suspend_booking_for_information(intent:, topic:, pending_question:)
      return update_information_task(intent:, topic:) unless booking_branch_present?

      update_booking_task(
        "status" => "suspended",
        "pending_question" => pending_question.presence || booking_pending_question,
        "branch" => booking_branch,
        "suspended" => true,
        "suspended_at" => now.iso8601,
        "expires_at" => (now + SUSPENDED_BOOKING_TTL).iso8601,
        "interruption_count" => booking_task["interruption_count"].to_i + 1,
        "last_interruption_intent" => intent,
        "last_interruption_topic" => topic
      ).then do |updated_payload|
        self.class.new(slots_payload: updated_payload, now: now).update_information_task(intent:, topic:)
      end
    end

    def update_information_task(intent:, topic:, question: nil)
      task = default_information_task.merge(
        "status" => "completed",
        "intent" => intent,
        "topic" => topic,
        "last_question" => question,
        "answered_at" => now.iso8601
      )

      without_legacy(payload.merge("information_task" => compact_blank_values(task)))
    end

    def resume_booking
      return [ payload, nil ] unless suspended_booking_resumable?

      resumed_task = booking_task.merge(
        "status" => status_for_pending_question(booking_task["pending_question"]),
        "suspended" => false,
        "suspended_at" => nil,
        "expires_at" => nil
      )

      [ without_legacy(payload.merge("booking_task" => resumed_task)), resumed_task ]
    end

    def archive_completed_booking
      return payload unless booking_branch_present?

      completed = Array(payload["completed_booking_branches"]).select { |entry| entry.is_a?(Hash) } + [
        {
          "branch_id" => booking_branch["branch_id"],
          "selected_option" => booking_branch["selected_option"],
          "completed_at" => now.iso8601
        }
      ]

      without_legacy(
        payload.merge(
          "booking_task" => default_booking_task,
          "completed_booking_branches" => completed.last(5)
        )
      )
    end

    def reset_tasks
      without_legacy(
        payload.merge(
          "booking_task" => default_booking_task,
          "information_task" => default_information_task,
          "completed_booking_branches" => []
        )
      )
    end

    def reset_booking_task
      without_legacy(payload.merge("booking_task" => default_booking_task))
    end

    private

    attr_reader :now

    def normalize_payload(value)
      source = value.is_a?(Hash) ? value.deep_dup : {}
      migrated = source["state_version"].to_i >= STATE_VERSION ? source : migrate_legacy(source)

      without_legacy(
        migrated.merge(
          "state_version" => STATE_VERSION,
          "booking_task" => normalize_booking_task(migrated["booking_task"]),
          "information_task" => normalize_information_task(migrated["information_task"]),
          "completed_booking_branches" => Array(migrated["completed_booking_branches"]).select { |entry| entry.is_a?(Hash) }
        )
      )
    end

    def migrate_legacy(source)
      active = source["active"] if source["active"].is_a?(Hash)
      paused = Array(source["paused_flows"]).select { |flow| flow.is_a?(Hash) && flow["topic"] == "booking_search" }.last

      booking_task = if paused.present?
        default_booking_task.merge(
          "status" => "suspended",
          "pending_question" => paused["pending_question"],
          "branch" => normalize_branch(paused["slots"]),
          "suspended" => true,
          "suspended_at" => paused["updated_at"],
          "expires_at" => paused["expires_at"]
        )
      elsif active.present?
        pending = source["pending_question"]
        default_booking_task.merge(
          "status" => status_for_pending_question(pending),
          "pending_question" => pending,
          "branch" => normalize_branch(active),
          "suspended" => false
        )
      else
        default_booking_task
      end

      source.merge("booking_task" => booking_task, "information_task" => default_information_task)
    end

    def normalize_booking_task(value)
      task = value.is_a?(Hash) ? value.deep_dup : {}
      default_booking_task.merge(task).tap do |normalized|
        normalized["branch"] = normalize_branch(normalized["branch"])
        normalized["status"] = "expired" if normalized["status"] == "suspended" && expired?(normalized)
      end
    end

    def normalize_information_task(value)
      task = value.is_a?(Hash) ? value.deep_dup : {}
      default_information_task.merge(task)
    end

    def update_booking_task(attributes)
      without_legacy(payload.merge("booking_task" => booking_task.merge(attributes)))
    end

    def normalize_branch(value)
      branch = value.is_a?(Hash) ? value.deep_dup : {}
      default_branch.merge(branch)
    end

    def booking_branch_present?
      branch = booking_branch
      branch.except("branch_id", "room_count", "suggestion_set_version", "suggested_options").values.any?(&:present?) || Array(branch["suggested_options"]).present?
    end

    def status_for_pending_question(pending_question)
      case pending_question
      when "select_option"
        "waiting_for_option_selection"
      when "confirm_selection"
        "waiting_for_confirmation"
      when "rate_plan_selection"
        "waiting_for_rate_plan_selection"
      when nil, ""
        "idle"
      else
        "collecting_slots"
      end
    end

    def expired?(task)
      expires_at = Time.zone.parse(task["expires_at"].to_s)
      expires_at.present? && expires_at <= now
    rescue ArgumentError
      false
    end

    def without_legacy(hash)
      hash.except("active", "paused_flows")
    end

    def compact_blank_values(hash)
      hash.reject { |_key, value| value.nil? }
    end

    def default_booking_task
      {
        "status" => "idle",
        "pending_question" => nil,
        "branch" => default_branch,
        "suspended" => false,
        "suspended_at" => nil,
        "expires_at" => nil,
        "interruption_count" => 0,
        "last_interruption_intent" => nil,
        "last_interruption_topic" => nil
      }
    end

    def default_information_task
      {
        "status" => "idle",
        "intent" => nil,
        "topic" => nil,
        "last_question" => nil,
        "answered_at" => nil
      }
    end

    def default_branch
      {
        "branch_id" => SecureRandom.uuid,
        "target_month" => nil,
        "target_year" => nil,
        "month_segment" => nil,
        "check_in" => nil,
        "check_out" => nil,
        "nights" => nil,
        "days" => nil,
        "room_count" => 1,
        "party_size_total" => nil,
        "adults" => nil,
        "children" => nil,
        "clarification_needed" => nil,
        "suggested_options" => [],
        "suggestion_set_version" => 0,
        "pending_selection" => nil,
        "confirmation_candidate" => nil,
        "selected_option" => nil,
        "selected_rate_plan_id" => nil,
        "selected_rate_plan_name" => nil
      }
    end
    end
  end
end
