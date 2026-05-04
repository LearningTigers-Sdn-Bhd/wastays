module AiConciergeV3
  class TransitionPolicy
    def initialize(interpretation:, active_branch:, paused_flows:, pending_question:, message: nil)
      @interpretation = interpretation
      @active_branch = active_branch || {}
      @paused_flows = Array(paused_flows)
      @pending_question = pending_question
      @message = message.to_s
    end

    def call
      return action(:reset) if interpretation.dig("conversation_signals", "is_reset")
      return action(:resume) if should_resume_paused_flow?
      return action(:confirmation_yes) if confirmation_yes?
      return action(:confirmation_no) if confirmation_no?
      return action(:option_selection) if interpretation["intent"] == "option_selection"
      return action(:hotel_policy, pause: booking_context_active?) if interpretation["intent"] == "hotel_policy"
      return action(:booking_context) if interpretation["intent"] == "booking_context"
      return action(:greeting) if interpretation["intent"] == "greeting"
      return action(:ask_booking_timing) if missing_timing?
      return action(:ask_duration) if missing_duration?
      return action(:ask_adult_count) if missing_adult_count?
      return action(:ask_guest_count) if missing_guest_count?
      return action(:ask_party_split) if missing_party_split?

      action(:search_options)
    end

    private

    attr_reader :interpretation, :active_branch, :paused_flows, :pending_question, :message

    def action(name, extra = {})
      { action: name }.merge(extra)
    end

    def confirmation_yes?
      interpretation["intent"] == "confirmation" && interpretation.dig("slots", "confirmation") != "no"
    end

    def confirmation_no?
      interpretation["intent"] == "confirmation" && interpretation.dig("slots", "confirmation") == "no"
    end

    def booking_context_active?
      active_branch.is_a?(Hash) && active_branch.present? && active_branch["target_month"].present?
    end

    def should_resume_paused_flow?
      paused_flows.present? && (
        interpretation.dig("conversation_signals", "is_resume") ||
        interpretation["intent"] == "option_selection" ||
        selection_like_follow_up?
      )
    end

    def selection_like_follow_up?
      return true if interpretation.dig("slots", "check_in").present?
      return true if interpretation.dig("slots", "option_number").present?

      room_type_mentioned_in_paused_flow?
    end

    def room_type_mentioned_in_paused_flow?
      names = Array(latest_paused_flow&.dig("slots", "suggested_options")).filter_map do |group|
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

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def missing_timing?
      active_branch["check_in"].blank? && active_branch["target_month"].blank?
    end

    def missing_duration?
      has_timing? && duration_missing?
    end

    def has_timing?
      active_branch["check_in"].present? || active_branch["target_month"].present?
    end

    def duration_missing?
      active_branch["check_out"].blank? &&
        active_branch["nights"].to_i <= 0 &&
        active_branch["days"].to_i <= 0
    end

    def missing_adult_count?
      active_branch["children"].to_i.positive? &&
        active_branch["adults"].to_i <= 0
    end

    def missing_guest_count?
      active_branch["party_size_total"].to_i <= 0 && 
        active_branch["adults"].to_i <= 0 && 
        active_branch["children"].to_i <= 0
    end

    def missing_party_split?
      active_branch["party_size_total"].to_i > 0 && 
        active_branch["adults"].to_i <= 0 && 
        active_branch["children"].to_i <= 0
    end
  end
end
