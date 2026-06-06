module AiConcierge
  module Orchestration
    module Core
      class TransitionPolicy
    def initialize(interpretation:, active_branch:, paused_flows: [], pending_question:, message: nil, booking_task: nil)
      @interpretation = interpretation
      @active_branch = active_branch || {}
      @paused_flows = Array(paused_flows)
      @pending_question = pending_question
      @message = message.to_s
      @booking_task = booking_task.is_a?(Hash) ? booking_task : {}
    end

    def call
      return action(:end_conversation) if interpretation.dig("conversation_signals", "end_conversation")
      return action(:reset) if interpretation.dig("conversation_signals", "is_reset")
      return action(:resume) if should_resume_paused_flow?

      return action(:librarian, pause: info_interruption_active?) if librarian_intent?
      return action(:booking_context) if interpretation["intent"] == "booking_context"
      return action(:booking, pending_question: pending_question) if pending_question.present?
      return action(:greeting) if interpretation["intent"] == "greeting"
      return action(:booking, pending_question: pending_question) if booking_intent?

      action(:fallback)
    end

    private

    attr_reader :interpretation, :active_branch, :paused_flows, :pending_question, :message, :booking_task

    def action(name, extra = {})
      { action: name }.merge(extra)
    end

    def librarian_intent?
      %w[hotel_policy hotel_information nearby_attractions room_information].include?(interpretation["intent"].to_s)
    end

    def booking_intent?
      %w[booking_search option_selection confirmation].include?(interpretation["intent"].to_s) || pending_question.present?
    end

    def info_interruption_active?
      active_branch.is_a?(Hash) && active_branch.present? && (
        active_branch["target_month"].present? ||
        active_branch["check_in"].present? ||
        pending_question.present?
      )
    end

    def should_resume_paused_flow?
      return false if librarian_intent?
      return false unless suspended_booking_resumable?

      confirmation_follow_up? || selection_follow_up? || interpretation["intent"] == "option_selection" || interpretation.dig("conversation_signals", "is_resume") || selection_like_follow_up? || booking_continuation_follow_up?
    end

    def suspended_booking_resumable?
      return false if booking_task["status"] == "expired" || suspended_booking_expired?

      booking_task["status"] == "suspended" || booking_task["suspended"] == true || paused_flows.present?
    end

    def suspended_booking_expired?
      expires_at = Time.zone.parse(booking_task["expires_at"].to_s)
      expires_at.present? && expires_at <= Time.current
    rescue ArgumentError
      false
    end

    def confirmation_follow_up?
      booking_task["pending_question"] == "confirm_selection" && interpretation["intent"] == "confirmation"
    end

    def selection_follow_up?
      booking_task["pending_question"] == "select_option" && interpretation["intent"] == "option_selection"
    end

    def selection_like_follow_up?
      return true if interpretation.dig("slots", "check_in").present?
      return true if interpretation.dig("slots", "option_number").present?

      room_type_mentioned_in_paused_flow?
    end

    def booking_continuation_follow_up?
      return true if interpretation["intent"] == "booking_search"
      return true if booking_slot_present?

      normalized = normalize(message)
      normalized.match?(/\b(?:book|booking|reserve|reservation|stay|quote|availability)\b/) ||
        normalized.match?(/\b(?:this month|next month|early|mid|late)\b/) ||
        normalized.match?(/\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|june|jul|july|aug|sep|sept|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\b(?:jan|feb|mar|apr|may|jun|june|jul|july|aug|sep|sept|oct|nov|dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?\b/) ||
        normalized.match?(/\b\d+\s+(?:days?|nights?)\b/)
    end

    def booking_slot_present?
      %w[target_month target_year month_segment check_in check_out nights days party_size_total adults children room_count].any? do |key|
        value = interpretation.dig("slots", key)
        value.present? && value != 0
      end
    end

    def room_type_mentioned_in_paused_flow?
      names = Array(resumable_suggested_options).filter_map do |group|
        group["room_type_name"] if group.is_a?(Hash)
      end
      normalized_message = normalize(message)

      names.any? do |name|
        room_tokens = normalize(name).split
        room_tokens.any? { |token| token.length > 2 && normalized_message.include?(token) }
      end
    end

    def latest_paused_flow
      @latest_paused_flow ||= paused_flows.reverse.find { |flow| flow.is_a?(Hash) && flow["topic"] == "booking_search" } || paused_flows.find { |flow| flow.is_a?(Hash) && flow["topic"] == "booking_search" }
    end

    def resumable_suggested_options
      booking_task.dig("branch", "suggested_options").presence || latest_paused_flow&.dig("slots", "suggested_options")
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
      end
    end
  end
end
