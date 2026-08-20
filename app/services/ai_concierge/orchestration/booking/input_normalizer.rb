module AiConcierge
  module Orchestration
    module Booking
      class InputNormalizer
    def initialize(message:, slots:, pending_question:, conversation_signals:, evidence: {}, active_branch: {})
      @message = message.to_s
      @slots = slots.is_a?(Hash) ? slots.deep_dup : {}
      @pending_question = pending_question
      @conversation_signals = conversation_signals.to_h
      @evidence = evidence.is_a?(Hash) ? evidence : {}
      @active_branch = active_branch.is_a?(Hash) ? active_branch : {}
    end

    def call
      return slots if conversation_signals["is_correction"]

      apply_date_range_answer!

      timing_keys = %w[target_month target_year month_segment check_in check_out]
      duration_keys = %w[days nights]
      party_keys = %w[party_size_total adults children]

      timing_keys.each { |key| slots.delete(key) } unless explicit_timing_in_message? || quoted?("timing")
      duration_keys.each { |key| slots.delete(key) } unless explicit_duration_in_message? || quoted?("duration")
      party_keys.each { |key| slots.delete(key) } unless party_evidence_in_message? || quoted?("party")
      slots.delete("check_out") unless explicit_checkout_in_message? || quoted?("checkout")
      apply_relative_month_timing!
      apply_guest_count_guards!

      case pending_question
      when "duration", "guest_count", "party_split", "confirm_selection", "select_option"
        timing_keys.each { |key| slots.delete(key) }
      when "specific_timing"
        # Keep timing slots when clarifying specific timing.
        apply_specific_timing_answer!
      when "date_range_month"
        apply_pending_date_range_month_answer!
      end

      strip_hallucinated_specific_dates!
      slots.delete("month_segment") if slots["month_segment"].present? && !message_contains_month_segment?
      slots
    end

    private

    attr_reader :message, :slots, :pending_question, :conversation_signals, :evidence, :active_branch

    # Every other guard here re-reads the message in English, which is why a
    # guest writing Malay or Chinese has correct slots deleted and is asked the
    # same question forever. This asks the model to quote the guest instead,
    # and only checks the quote is really there.
    #
    # Deliberately no digit test: "两位大人" says two adults without a 2 in it,
    # and a check for numerals would rebuild the same wall in a new place. What
    # this catches is the model filling a slot from nothing -- asked which
    # words say the party size, a message that never mentioned people has
    # nothing to quote.
    def quoted?(kind)
      span = normalize_for_quote(evidence[kind])
      return false if span.blank?

      normalize_for_quote(message).include?(span)
    end

    def normalize_for_quote(value)
      value.to_s.downcase.gsub(/\s+/, " ").strip
    end

    def apply_date_range_answer!
      range = parse_complete_date_range
      if range
        apply_date_range_slots!(range)
        return
      end

      partial = parse_partial_day_range
      return unless partial
      return unless date_range_clarification_allowed?

      slots.delete("check_in")
      slots.delete("check_out")
      slots.delete("target_month")
      slots.delete("target_year")
      slots.delete("month_segment")
      slots.delete("days")
      slots.delete("nights")
      slots["clarification_needed"] = {
        "type" => "date_range_month",
        "start_day" => partial[:start_day],
        "end_day" => partial[:end_day]
      }
    end

    def apply_pending_date_range_month_answer!
      return if slots["check_in"].present? && slots["check_out"].present?

      clarification = active_branch["clarification_needed"]
      return unless clarification.is_a?(Hash) && clarification["type"] == "date_range_month"

      month_year = month_year_from_message(message.downcase)
      return unless month_year

      range = build_date_range(
        start_day: clarification["start_day"].to_i,
        start_month: month_year[:month],
        start_year: month_year[:year],
        end_day: clarification["end_day"].to_i,
        end_month: month_year[:month],
        end_year: month_year[:year]
      )
      return unless range

      apply_date_range_slots!(range)
    end

    def parse_complete_date_range
      normalized = normalized_message

      range = parse_day_month_to_day_month_range(normalized)
      return range if range

      range = parse_month_day_to_month_day_range(normalized)
      return range if range

      range = parse_month_day_to_day_range(normalized)
      return range if range

      range = parse_day_month_to_day_range(normalized)
      return range if range

      parse_same_month_day_range(normalized)
    end

    def parse_same_month_day_range(normalized)
      match = normalized.match(/\b(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|\s+)\s*(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})\b/)
      return unless match

      month = month_number(match[3])
      year = year_from_message(normalized) || Date.current.year
      build_date_range(start_day: match[1].to_i, start_month: month, start_year: year, end_day: match[2].to_i, end_month: month, end_year: year)
    end

    def parse_day_month_to_day_month_range(normalized)
      match = normalized.match(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})\s*(?:-|to|until|till)?\s+(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})(?:\s+(20\d{2}))?\b/)
      return unless match

      start_month = month_number(match[2])
      end_month = month_number(match[4])
      years = date_range_years(start_month: start_month, end_month: end_month, explicit_end_year: match[5], normalized: normalized)
      build_date_range(start_day: match[1].to_i, start_month: start_month, start_year: years[:start_year], end_day: match[3].to_i, end_month: end_month, end_year: years[:end_year])
    end

    def parse_month_day_to_month_day_range(normalized)
      match = normalized.match(/\b(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|to|until|till)?\s+(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(20\d{2}))?\b/)
      return unless match

      start_month = month_number(match[1])
      end_month = month_number(match[3])
      years = date_range_years(start_month: start_month, end_month: end_month, explicit_end_year: match[5], normalized: normalized)
      build_date_range(start_day: match[2].to_i, start_month: start_month, start_year: years[:start_year], end_day: match[4].to_i, end_month: end_month, end_year: years[:end_year])
    end

    def parse_month_day_to_day_range(normalized)
      match = normalized.match(/\b(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|to|until|till|\s+)\s*(\d{1,2})(?:st|nd|rd|th)?(?:\s+(20\d{2}))?\b/)
      return unless match

      month = month_number(match[1])
      year = (match[4] || year_from_message(normalized) || Date.current.year).to_i
      build_date_range(start_day: match[2].to_i, start_month: month, start_year: year, end_day: match[3].to_i, end_month: month, end_year: year)
    end

    def parse_day_month_to_day_range(normalized)
      match = normalized.match(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})\s*(?:-|to|until|till)\s*(\d{1,2})(?:st|nd|rd|th)?(?:\s+(20\d{2}))?\b/)
      return unless match

      month = month_number(match[2])
      year = (match[4] || year_from_message(normalized) || Date.current.year).to_i
      build_date_range(start_day: match[1].to_i, start_month: month, start_year: year, end_day: match[3].to_i, end_month: month, end_year: year)
    end

    def parse_partial_day_range
      return if normalized_message.match?(/\b#{month_pattern}\b/)

      match = normalized_message.match(/\A\s*(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|\s+)\s*(\d{1,2})(?:st|nd|rd|th)?\s*\z/)
      return unless match

      { start_day: match[1].to_i, end_day: match[2].to_i }
    end

    def apply_date_range_slots!(range)
      slots["target_month"] = range[:check_in].month
      slots["target_year"] = range[:check_in].year
      slots["check_in"] = range[:check_in].iso8601
      slots["check_out"] = range[:check_out].iso8601
      slots["nights"] = (range[:check_out] - range[:check_in]).to_i
      slots["days"] = slots["nights"] + 1
      slots.delete("month_segment")
      slots.delete("confirmation")
      slots["clarification_needed"] = ""
    end

    def build_date_range(start_day:, start_month:, start_year:, end_day:, end_month:, end_year:)
      check_in = Date.new(start_year.to_i, start_month.to_i, start_day.to_i)
      check_out = Date.new(end_year.to_i, end_month.to_i, end_day.to_i)
      check_out = check_out.next_year if check_out <= check_in && end_month.to_i < start_month.to_i
      return if check_out <= check_in

      { check_in: check_in, check_out: check_out }
    rescue Date::Error
      nil
    end

    def date_range_years(start_month:, end_month:, explicit_end_year:, normalized:)
      year = (explicit_end_year || year_from_message(normalized) || Date.current.year).to_i
      start_year = explicit_end_year.present? && end_month.to_i < start_month.to_i ? year - 1 : year

      { start_year: start_year, end_year: year }
    end

    def date_range_clarification_allowed?
      pending_question.blank? || %w[booking_timing specific_timing date_range_month].include?(pending_question.to_s)
    end

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

    def month_year_from_message(normalized)
      relative = relative_month_date
      return { month: relative.month, year: relative.year } if relative

      month = month_from_message(normalized)
      return unless month

      year = year_from_message(normalized)
      year ||= month < Date.current.month ? Date.current.next_year.year : Date.current.year
      { month: month, year: year }
    end

    def month_number(name)
      MONTH_NAMES.each_with_index do |names, index|
        return index + 1 if names.include?(name.downcase)
      end
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
      return if resolving_pending_date_range?

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

    def resolving_pending_date_range?
      clarification = active_branch["clarification_needed"]
      pending_question == "date_range_month" && clarification.is_a?(Hash) && clarification["type"] == "date_range_month"
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
        normalized.match?(/\b\d+\s+months?\s+from\s+now\b/) ||
        parse_complete_date_range.present? ||
        parse_partial_day_range.present? ||
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
      return Date.current.advance(months: normalized[/\b(\d+)\s+months?\s+from\s+now\b/, 1].to_i) if normalized.match?(/\b\d+\s+months?\s+from\s+now\b/)

      nil
    end

    def normalized_message
      message.downcase.gsub(/[–—]/, "-").squish
    end

    def month_pattern
      @month_pattern ||= MONTH_NAMES.flatten.map { |name| Regexp.escape(name) }.join("|")
    end

    def explicit_duration_in_message?
      normalized = message.downcase

      normalized.match?(/\b\d+\s*nights?\b/) ||
        normalized.match?(/\b\d+\s*days?\b/) ||
        parse_complete_date_range.present? ||
        normalized.match?(/\bstay(?:ing)?\s+for\s+\d+\s*(?:days?|nights?)\b/) ||
        normalized.match?(/\bfor\s+\d+\s*(?:days?|nights?)\b/)
    end

    def explicit_checkout_in_message?
      normalized = message.downcase

      normalized.match?(/\bcheck\s*out\b/) ||
        normalized.match?(/\bfrom\b.*\bto\b/) ||
        normalized.match?(/\buntil\b/) ||
        normalized.match?(/\btill\b/) ||
        parse_complete_date_range.present? ||
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

    # A party size is only believed when the turn actually carries one: the
    # guest said it, or the hotel asked and this is the answer. Without this
    # the model's "adults: 1" on a message about nights becomes a price nobody
    # was asked to agree to.
    def party_evidence_in_message?
      return true if explicit_people_total_in_message?
      return true if explicit_adults_in_message?
      return true if explicit_children_in_message?

      %w[guest_count party_split].include?(pending_question)
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
end
