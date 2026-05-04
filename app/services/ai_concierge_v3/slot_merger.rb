module AiConciergeV3
  class SlotMerger
    DOWNSTREAM_KEYS = %w[suggested_options confirmation_candidate selected_option suggestion_set_version pending_selection].freeze
    TIMING_KEYS = %w[target_month target_year month_segment check_in check_out nights days].freeze
    PARTY_KEYS = %w[party_size_total adults children room_count].freeze

    def initialize(active_branch:, slots:, pending_question:, message:)
      @active_branch = active_branch.is_a?(Hash) ? active_branch.deep_dup : default_branch
      @slots = slots.is_a?(Hash) ? slots : {}
      @pending_question = pending_question
      @message = message.to_s
    end

    def call
      branch = active_branch.deep_dup
      previous_timing = branch.slice(*TIMING_KEYS)
      previous_party = branch.slice(*PARTY_KEYS)

      merge_slots(branch)
      resolve_people_clarification(branch)

      clear_downstream!(branch) if previous_timing != branch.slice(*TIMING_KEYS)
      clear_downstream!(branch) if previous_party != branch.slice(*PARTY_KEYS)

      branch
    end

    private

    attr_reader :active_branch, :slots, :pending_question, :message

    def merge_slots(branch)
      slots.each do |key, value|
        next if value.nil? || value == 0

        branch[key.to_s] = value
      end

      normalize_duration!(branch)

      # Only default rooms to 1 if we're in a booking flow
      branch["room_count"] ||= 1 if branch["target_month"].present? || branch["check_in"].present?
      branch["party_size_total"] ||= total_party_size(branch)
    end

    def resolve_people_clarification(branch)
      if pending_question == "party_split" && branch["party_size_total"].to_i.positive?
        if message.match?(/\badults?\b/i) && !message.match?(/\bchildren?\b/i)
          branch["adults"] = branch["party_size_total"]
          branch["children"] = 0
        elsif message.match?(/\bchildren?\b/i) && !message.match?(/\badults?\b/i)
          branch["adults"] = 0
          branch["children"] = branch["party_size_total"]
        end
      end
    end

    def clear_downstream!(branch)
      DOWNSTREAM_KEYS.each { |key| branch[key] = default_branch[key] }
    end

    def total_party_size(branch)
      adults = branch["adults"].to_i
      children = branch["children"].to_i
      total = adults + children
      total.positive? ? total : nil
    end

    def normalize_duration!(branch)
      if branch["nights"].to_i.positive? && branch["days"].to_i <= 0
        branch["days"] = branch["nights"].to_i + 1
      elsif branch["days"].to_i.positive? && branch["nights"].to_i <= 0
        branch["nights"] = branch["days"].to_i - 1
      end

      return if branch["check_in"].blank?
      return if branch["check_out"].present?
      return unless branch["nights"].to_i.positive?

      check_in = Date.parse(branch["check_in"].to_s)
      branch["check_out"] = (check_in + branch["nights"].to_i.days).iso8601
    rescue Date::Error
      nil
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
        "selected_option" => nil
      }
    end
  end
end
