module AiConcierge
  module State
    class SlotMerger
    DOWNSTREAM_KEYS = %w[suggested_options confirmation_candidate selected_option suggestion_set_version selected_rate_plan_id selected_rate_plan_name].freeze
    TIMING_KEYS = %w[target_month target_year month_segment check_in check_out nights days].freeze
    PARTY_KEYS = %w[party_size_total adults children room_count].freeze

    def self.empty_branch
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
        "confirmation_candidate" => nil,
        "selected_option" => nil,
        "selected_rate_plan_id" => nil,
        "selected_rate_plan_name" => nil
      }
    end

    def initialize(active_branch:, slots:, pending_question:, message:)
      @active_branch = active_branch.is_a?(Hash) ? active_branch.deep_dup : self.class.empty_branch
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
      derive_month_from_check_in!(branch)

      # Only default rooms to 1 if we're in a booking flow
      branch["room_count"] ||= 1 if branch["target_month"].present? || branch["check_in"].present?
      branch["party_size_total"] ||= total_party_size(branch)
    end

    def resolve_people_clarification(branch)
      return unless pending_question == "party_split" && branch["party_size_total"].to_i.positive?

      total = branch["party_size_total"].to_i
      says_adults = message.match?(/\badults?\b/i)
      says_children = message.match?(/\bchildren?\b/i) || message.match?(/\bchild\b/i) || message.match?(/\bkids?\b/i)

      # Which of the two the guest just answered with. The English words are
      # the reading when they are there; otherwise the shape of what the model
      # extracted says the same thing, in any language -- a message naming only
      # adults is a message about adults.
      says_adults ||= slots.key?("adults") && !slots.key?("children") unless says_children
      says_children ||= slots.key?("children") && !slots.key?("adults") unless says_adults

      is_adults_msg = says_adults && !says_children
      is_children_msg = says_children && !says_adults

      if is_adults_msg
        adults_count = branch["adults"].to_i
        if adults_count.positive? && adults_count < total
          branch["children"] = nil
        elsif adults_count >= total
          branch["adults"] = total
          branch["children"] = 0
        else
          extracted = message.downcase[/\b(\d+)\s+adults?\b/, 1].to_i
          if extracted.positive? && extracted < total
            branch["adults"] = extracted
            branch["children"] = nil
          else
            branch["adults"] = total
            branch["children"] = 0
          end
        end
        return
      elsif is_children_msg
        children_count = branch["children"].to_i
        if children_count.positive? && children_count < total
          branch["adults"] = nil
        elsif children_count >= total
          branch["adults"] = 0
          branch["children"] = total
        else
          extracted = message.downcase[/\b(\d+)\s+children?\b/, 1].to_i || message.downcase[/\b(\d+)\s+child\b/, 1].to_i || message.downcase[/\b(\d+)\s+kids?\b/, 1].to_i
          if extracted.positive? && extracted < total
            branch["children"] = extracted
            branch["adults"] = nil
          else
            branch["adults"] = 0
            branch["children"] = total
          end
        end
        return
      end

      if slots["confirmation"] == "yes"
        if branch["adults"].to_i.positive? && branch["children"].nil?
          branch["children"] = total - branch["adults"].to_i
        elsif branch["children"].to_i.positive? && branch["adults"].nil?
          branch["adults"] = total - branch["children"].to_i
        end
      elsif slots["confirmation"] == "no"
        branch["adults"] = nil
        branch["children"] = nil
      end
    end

    # A date already says which month it is in. SearchBookingOptionsTool bails
    # out with no options when target_month is blank, so a model that returns
    # check_in alone -- perfectly correct extraction -- would have the guest
    # told there is nothing available.
    def derive_month_from_check_in!(branch)
      return if branch["check_in"].blank?
      return if branch["target_month"].present? && branch["target_year"].present?

      check_in = Date.parse(branch["check_in"].to_s)
      branch["target_month"] = check_in.month
      branch["target_year"] = check_in.year
    rescue Date::Error
      nil
    end

    def clear_downstream!(branch)
      empty = self.class.empty_branch
      DOWNSTREAM_KEYS.each { |key| branch[key] = empty[key] }
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
      self.class.empty_branch
    end
    end
  end
end
