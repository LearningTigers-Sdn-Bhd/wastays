module AiConciergeV3
  module Orchestration
    class BookingInputNormalizer
    def initialize(message:, slots:, pending_question:, conversation_signals:, active_branch: {})
      @message = message.to_s
      @slots = slots.is_a?(Hash) ? slots.deep_dup : {}
      @pending_question = pending_question
      @conversation_signals = conversation_signals.to_h
      @active_branch = active_branch.is_a?(Hash) ? active_branch : {}
    end

    def call
      return slots if conversation_signals["is_correction"]

      timing_keys = %w[target_month target_year month_segment check_in check_out]
      duration_keys = %w[days nights]

      timing_keys.each { |key| slots.delete(key) } unless explicit_timing_in_message?
      duration_keys.each { |key| slots.delete(key) } unless explicit_duration_in_message?
      slots.delete("check_out") unless explicit_checkout_in_message?
      apply_relative_month_timing!
      apply_guest_count_guards!

      case pending_question
      when "duration", "guest_count", "party_split", "confirm_selection", "select_option"
        timing_keys.each { |key| slots.delete(key) }
      when "specific_timing"
        # Keep timing slots when clarifying specific timing.
        apply_specific_timing_answer!
      end

      strip_hallucinated_specific_dates!
      slots.delete("month_segment") if slots["month_segment"].present? && !message_contains_month_segment?
      slots
    end

    private

    attr_reader :message, :slots, :pending_question, :conversation_signals, :active_branch

    def apply_specific_timing_answer!
      parsed = parse_specific_date_answer
      return unless parsed

      slots["target_month"] = parsed.month
      slots["target_year"] = parsed.year
      slots["check_in"] = parsed.iso8601
      slots.delete("month_segment")
      slots.delete("confirmation")
    end

    def parse_specific_date_answer
      normalized = message.downcase
      month = month_from_message(normalized)
      day = day_from_message(normalized)
      return unless day

      month ||= active_branch["target_month"].presence || slots["target_month"].presence
      year = year_from_message(normalized) || active_branch["target_year"].presence || slots["target_year"].presence || Date.current.year
      return unless month

      Date.new(year.to_i, month.to_i, day.to_i)
    rescue Date::Error
      nil
    end

    def month_from_message(normalized)
      MONTH_NAMES.each_with_index do |names, index|
        return index + 1 if names.any? { |name| normalized.match?(/\b#{Regexp.escape(name)}\b/) }
      end

      slash_month = normalized[/\b\d{1,2}\s*[\/-]\s*(\d{1,2})(?:\s*[\/-]\s*\d{2,4})?\b/, 1]
      slash_month&.to_i
    end

    def day_from_message(normalized)
      day = normalized[/\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b/, 1] ||
            normalized[/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?\b/, 1] ||
            normalized[/\b(\d{1,2})\s*[\/-]\s*\d{1,2}(?:\s*[\/-]\s*\d{2,4})?\b/, 1]

      day ||= normalized[/\b(\d{1,2})(?:st|nd|rd|th)?\b/, 1] if active_branch["target_month"].present? || slots["target_month"].present?
      day&.to_i
    end

    def year_from_message(normalized)
      normalized[/\b(20\d{2})\b/, 1]&.to_i
    end

    def strip_hallucinated_specific_dates!
      return unless slots["check_in"].present? && !message_contains_specific_date?

      begin
        parsed_date = Date.parse(slots["check_in"])
        slots["target_month"] = parsed_date.month if slots["target_month"].blank?
        slots["target_year"] = parsed_date.year if slots["target_year"].blank?
      rescue Date::Error
        # Ignore parse errors.
      end
      slots.delete("check_in")
      slots.delete("check_out")
    end

    def message_contains_specific_date?
      normalized = message.downcase
      return true if normalized.match?(/\d/)

      normalized.match?(/\b(?:tomorrow|today|tonight|next week|this weekend|next weekend|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/)
    end

    def message_contains_month_segment?
      message.downcase.match?(/\b(?:early|mid|late)\b/)
    end

    def explicit_timing_in_message?
      normalized = message.downcase
      return true if pending_question == "specific_timing" && normalized.match?(/\b(?:early|mid|late)\b/)
      return true if pending_question == "specific_timing" && parse_specific_date_answer.present?

      normalized.match?(/\b(?:early|mid|late)\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\b(?:this|next)\s+month\b/) ||
        normalized.match?(/\bnext month\b/) ||
        normalized.match?(/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?\b/) ||
        normalized.match?(/\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\b\d{4}-\d{2}-\d{2}\b/)
    end

    def apply_relative_month_timing!
      target = relative_month_date
      return unless target

      slots["target_month"] = target.month
      slots["target_year"] = target.year
      slots["month_segment"] = message_contains_month_segment? ? message.downcase[/\b(early|mid|late)\b/, 1] : ""
      slots.delete("check_in") unless message_contains_specific_date?
      slots.delete("check_out") unless explicit_checkout_in_message?
    end

    def relative_month_date
      normalized = message.downcase
      return Date.current if normalized.match?(/\bthis\s+month\b/)
      return Date.current.next_month if normalized.match?(/\bnext\s+month\b/)

      nil
    end

    def explicit_duration_in_message?
      normalized = message.downcase

      normalized.match?(/\b\d+\s*nights?\b/) ||
        normalized.match?(/\b\d+\s*days?\b/) ||
        normalized.match?(/\bstay(?:ing)?\s+for\s+\d+\s*(?:days?|nights?)\b/) ||
        normalized.match?(/\bfor\s+\d+\s*(?:days?|nights?)\b/)
    end

    def explicit_checkout_in_message?
      normalized = message.downcase

      normalized.match?(/\bcheck\s*out\b/) ||
        normalized.match?(/\bfrom\b.*\bto\b/) ||
        normalized.match?(/\buntil\b/) ||
        normalized.match?(/\btill\b/) ||
        normalized.scan(/\b\d{4}-\d{2}-\d{2}\b/).size >= 2 ||
        normalized.scan(/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?\b/).size >= 2 ||
        normalized.scan(/\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/).size >= 2
    end

    def apply_guest_count_guards!
      if explicit_people_total_in_message?
        slots["party_size_total"] = extracted_people_total if extracted_people_total.positive?
        slots.delete("adults") unless explicit_adults_in_message?
        slots.delete("children") unless explicit_children_in_message?
      else
        slots.delete("party_size_total")
      end

      if explicit_adults_in_message? && !explicit_children_in_message?
        slots["adults"] = extracted_adult_count if extracted_adult_count.positive?
        slots.delete("children") unless explicit_people_total_in_message?
      end

      slots["children"] = extracted_children_count if explicit_children_in_message? && !explicit_adults_in_message? && extracted_children_count.positive?
    end

    def explicit_people_total_in_message?
      message.downcase.match?(/\b\d+\s+peoples?\b/) ||
        message.downcase.match?(/\b\d+\s+pax\b/) ||
        (pending_question == "guest_count" && message.strip.match?(/\A\d+\z/))
    end

    def explicit_adults_in_message?
      message.downcase.match?(/\badults?\b/)
    end

    def explicit_children_in_message?
      message.downcase.match?(/\bchildren\b/) || message.downcase.match?(/\bchild\b/) || message.downcase.match?(/\bkids?\b/)
    end

    def extracted_people_total
      res = message.downcase[/\b(\d+)\s+peoples?\b/, 1] ||
            message.downcase[/\b(\d+)\s+pax\b/, 1] ||
            (pending_question == "guest_count" ? message.strip[/\A\d+\z/] : nil)
      res&.to_i || 0
    end

    def extracted_adult_count
      message.downcase[/\b(\d+)\s+adults?\b/, 1]&.to_i || 0
    end

    def extracted_children_count
      res = message.downcase[/\b(\d+)\s+children\b/, 1] ||
            message.downcase[/\b(\d+)\s+child\b/, 1] ||
            message.downcase[/\b(\d+)\s+kids?\b/, 1]
      res&.to_i || 0
    end

    MONTH_NAMES = [
      %w[jan january],
      %w[feb february],
      %w[mar march],
      %w[apr april],
      %w[may],
      %w[jun june],
      %w[jul july],
      %w[aug august],
      %w[sep sept september],
      %w[oct october],
      %w[nov november],
      %w[dec december]
    ].freeze
    end
  end
end
