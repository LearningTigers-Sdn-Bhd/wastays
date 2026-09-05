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

    # Named against the branch schema rather than restated here -- see
    # `State::SlotMerger`, which owns the shape these are keys of.
    TIMING_SLOT_KEYS = State::SlotMerger::DATE_KEYS
    DURATION_SLOT_KEYS = State::SlotMerger::DURATION_KEYS
    PARTY_SLOT_KEYS = State::SlotMerger::GUEST_KEYS
    SEARCH_SLOT_KEYS = State::SlotMerger::SEARCH_KEYS

    def call
      return slots if conversation_signals["is_correction"]
      return strip_search_slots! if row_reference_answer?

      apply_date_range_answer!

      timing_keys = TIMING_SLOT_KEYS
      duration_keys = DURATION_SLOT_KEYS
      party_keys = PARTY_SLOT_KEYS

      timing_keys.each { |key| slots.delete(key) } unless explicit_timing_in_message? || time_quoted?("timing")
      duration_keys.each { |key| slots.delete(key) } unless explicit_duration_in_message? || quoted?("duration")
      party_keys.each { |key| slots.delete(key) } unless party_evidence_in_message? || party_quoted?("party")
      slots.delete("check_out") unless explicit_checkout_in_message? || time_quoted?("checkout")
      apply_relative_month_timing!
      apply_month_segment!
      apply_duration_answer!
      apply_guest_count_guards!

      case pending_question
      when "duration", "guest_count", "party_split", "confirm_selection", "select_option"
        timing_keys.each { |key| slots.delete(key) } unless message_names_a_month?
      when "specific_timing"
        # Keep timing slots when clarifying specific timing.
        apply_specific_timing_answer!
      when "date_range_month"
        apply_pending_date_range_month_answer!
      end

      strip_hallucinated_specific_dates!
      roll_implicit_past_check_in!
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

    # A quote about time has to be about time.
    #
    # `quoted?` proves only that the words are the guest's own, and the model
    # is told today's date: "how to make booking" comes back as this month
    # with "booking" quoted as the words that say when they arrive. True, and
    # nothing to do with time. A date only survives here when the words behind
    # it carry a number, a month or a word for when.
    #
    # The vocabulary below is exactly the cost `quoted?` was written to avoid,
    # and it is accepted here because it is short, additive, and can only ever
    # fail safe: a language missing from it loses a date the guest really did
    # give, and the ladder asks for it again. It cannot invent one.
    TIME_MARKERS = %w[
      0 1 2 3 4 5 6 7 8 9
      〇 零 一 二 三 四 五 六 七 八 九 十
      jan feb mar apr may jun jul aug sep oct nov dec
      januari februari mac mei julai ogos oktober disember
      today tonight tomorrow day night week weekend month year
      hari esok malam minggu bulan tahun hb
      月 日 号 號 今天 明天 后天 週 周末 下周
    ].freeze

    # The two questions whose answer is a row number.
    LIST_PENDING_QUESTIONS = %w[select_option rate_plan_selection].freeze

    # "no 2" answering "which rate would you like?" is the second rate, and
    # nothing else. Read as slots it has been two nights, two rooms and two
    # adults on different turns -- each of which changes the search, which
    # discards the room the guest had already chosen and leaves the rate
    # question with no room to ask about.
    #
    # A message that says nothing but a row cannot change what was searched
    # for, so none of it is read as a slot. Anything else in the message --
    # "2 nights", "change to september" -- has words in it and takes the
    # ordinary path below.
    def row_reference_answer?
      return false unless LIST_PENDING_QUESTIONS.include?(pending_question)

      option_reference.only_reference?
    end

    def option_reference
      @option_reference ||= Matching::OptionReference.new(message: message)
    end

    def strip_search_slots!
      SEARCH_SLOT_KEYS.each { |key| slots.delete(key) }
      slots
    end

    # A quote about the party has to name people.
    #
    # Same shape as `time_quoted?` and the same reason: `quoted?` proves only
    # that the words are the guest's own. "option 1" is the guest's own words
    # and comes back quoted as the ones that say how many are staying -- so the
    # catalogue is thrown away as a party change and the guest, who was picking
    # a room, is asked how many of them are children.
    #
    # Digits alone cannot say who is staying; in the middle of an option list
    # they say which row. Anything else in the span -- in any language, which
    # is the point -- is taken as a word about people.
    def party_quoted?(kind)
      return false unless quoted?(kind)

      remainder = normalize_for_quote(evidence[kind]).gsub(/\d+/, " ")
      Matching::OptionReference::FILLER.each { |token| remainder = remainder.gsub(/\b#{token}\b/, " ") }
      remainder.match?(/[[:alpha:]]/)
    end

    def time_quoted?(kind)
      return false unless quoted?(kind)

      span = normalize_for_quote(evidence[kind])
      TIME_MARKERS.any? { |marker| span.include?(marker) }
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
      stated_year = year_from_message(normalized)
      year = stated_year || Date.current.year
      build_date_range(start_day: match[1].to_i, start_month: month, start_year: year, end_day: match[2].to_i, end_month: month, end_year: year, implicit_year: stated_year.nil?)
    end

    def parse_day_month_to_day_month_range(normalized)
      match = normalized.match(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})\s*(?:-|to|until|till)?\s+(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})(?:\s+(20\d{2}))?\b/)
      return unless match

      start_month = month_number(match[2])
      end_month = month_number(match[4])
      years = date_range_years(start_month: start_month, end_month: end_month, explicit_end_year: match[5], normalized: normalized)
      build_date_range(start_day: match[1].to_i, start_month: start_month, start_year: years[:start_year], end_day: match[3].to_i, end_month: end_month, end_year: years[:end_year], implicit_year: years[:implicit])
    end

    def parse_month_day_to_month_day_range(normalized)
      match = normalized.match(/\b(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|to|until|till)?\s+(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s+(20\d{2}))?\b/)
      return unless match

      start_month = month_number(match[1])
      end_month = month_number(match[3])
      years = date_range_years(start_month: start_month, end_month: end_month, explicit_end_year: match[5], normalized: normalized)
      build_date_range(start_day: match[2].to_i, start_month: start_month, start_year: years[:start_year], end_day: match[4].to_i, end_month: end_month, end_year: years[:end_year], implicit_year: years[:implicit])
    end

    def parse_month_day_to_day_range(normalized)
      match = normalized.match(/\b(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?\s*(?:-|to|until|till|\s+)\s*(\d{1,2})(?:st|nd|rd|th)?(?:\s+(20\d{2}))?\b/)
      return unless match

      month = month_number(match[1])
      stated_year = match[4] || year_from_message(normalized)
      year = (stated_year || Date.current.year).to_i
      build_date_range(start_day: match[2].to_i, start_month: month, start_year: year, end_day: match[3].to_i, end_month: month, end_year: year, implicit_year: stated_year.nil?)
    end

    def parse_day_month_to_day_range(normalized)
      match = normalized.match(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})\s*(?:-|to|until|till)\s*(\d{1,2})(?:st|nd|rd|th)?(?:\s+(20\d{2}))?\b/)
      return unless match

      month = month_number(match[2])
      stated_year = match[4] || year_from_message(normalized)
      year = (stated_year || Date.current.year).to_i
      build_date_range(start_day: match[1].to_i, start_month: month, start_year: year, end_day: match[3].to_i, end_month: month, end_year: year, implicit_year: stated_year.nil?)
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

    # A year the guest did not say is the year that has not happened yet.
    #
    # "3-5 january" said in August is next January, and filling in this year
    # instead asks Postgres for inventory rows that cannot exist: the search
    # comes back empty and the guest is told the hotel is full. Every
    # cross-year enquiry -- the whole high season -- failed that way.
    #
    # Only an implicit year rolls. "3-5 january 2026" is the guest's own
    # statement, wrong or not, and moving it silently would answer a question
    # they did not ask; that date is caught further up the ladder and said out
    # loud instead. Both ends move together, so the stay keeps its length and
    # the December-to-January wrap below survives the roll.
    def build_date_range(start_day:, start_month:, start_year:, end_day:, end_month:, end_year:, implicit_year: false)
      check_in = Date.new(start_year.to_i, start_month.to_i, start_day.to_i)
      check_out = Date.new(end_year.to_i, end_month.to_i, end_day.to_i)
      check_out = check_out.next_year if check_out <= check_in && end_month.to_i < start_month.to_i
      return if check_out <= check_in

      if implicit_year && check_in < Date.current
        check_in = check_in.next_year
        check_out = check_out.next_year
      end

      { check_in: check_in, check_out: check_out }
    rescue Date::Error
      nil
    end

    def date_range_years(start_month:, end_month:, explicit_end_year:, normalized:)
      stated_year = explicit_end_year.presence || year_from_message(normalized)
      year = (stated_year || Date.current.year).to_i
      start_year = explicit_end_year.present? && end_month.to_i < start_month.to_i ? year - 1 : year

      { start_year: start_year, end_year: year, implicit: stated_year.nil? }
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
      stated_year = year_from_message(normalized)
      year = stated_year || active_branch["target_year"].presence || slots["target_year"].presence || Date.current.year
      return unless month

      date = Date.new(year.to_i, month.to_i, day.to_i)
      # Same rule as the ranges above, and a year carried on the branch counts
      # as implicit: it was derived, and may itself be a year this bug wrote.
      date = date.next_year if stated_year.nil? && date < Date.current
      date
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
      return unless slots["check_in"].present? && !message_names_a_day?
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

    # A date the model handed over is read the same way as one parsed here.
    #
    # `build_date_range` already rolls a year the guest did not say, and says
    # why. But it only ever ran on dates this class read out of the message: a
    # check_in that arrived in the model's slots went round it, kept the year
    # nobody stated, and landed in the past -- where the ladder stops the thread
    # to say the date has gone. Same rule, same reason, the other door.
    #
    # A year the guest did state is left alone here too. That date is theirs,
    # wrong or not, and it is named out loud further up the ladder.
    def roll_implicit_past_check_in!
      check_in = slot_date("check_in")
      return if check_in.blank? || check_in >= Date.current
      return if year_from_message(message.downcase)

      rolled = check_in.next_year
      slots["check_in"] = rolled.iso8601
      slots["target_year"] = rolled.year if slots["target_year"].present?
      check_out = slot_date("check_out")
      slots["check_out"] = check_out.next_year.iso8601 if check_out
    end

    def slot_date(key)
      value = slots[key]
      return if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def resolving_pending_date_range?
      clarification = active_branch["clarification_needed"]
      pending_question == "date_range_month" && clarification.is_a?(Hash) && clarification["type"] == "date_range_month"
    end

    # Nouns that spend a number on something other than a date.
    #
    # Kept as words rather than as a rule because there is no rule: "3 days 2
    # nights" and "2 dewasa" are the same shape as "3 january", and the only
    # thing that tells them apart is knowing what the noun counts. Additive and
    # fail-safe in the same way TIME_MARKERS is -- a noun missing from here
    # leaves its number unexplained, which keeps a date rather than losing one.
    COUNTED_NOUNS = %w[
      days? nights? weeks? months? pax
      adults? child children kids? guests? persons? people rooms?
      hari malam minggu bulan dewasa kanak budak orang bilik
      天 晚 夜 周 位 人 大人 小孩 儿童 兒童 间 間 房 泊
    ].freeze

    # Whether the guest named a day of the month.
    #
    # This used to ask whether the message had a digit anywhere in it, which is
    # true of every duration and every party size ever written down. So "early
    # august for 3 days 2 nights" counted as a stated date, the day the model
    # invented to go with it was believed, and a guest who named a month was
    # told the first of it had already passed -- to which the only answer is to
    # say the month again, which reproduces it exactly.
    #
    # The reading is subtraction rather than recognition: take away the numbers
    # the message has already spent on nights and guests, and a day is what is
    # left over. That works in languages this file cannot otherwise read, and
    # when it does not, it fails towards keeping the date.
    # Whether the message names a month, at a question whose answer is a number.
    #
    # These five questions are answered with a count or a row, so a number in
    # the reply is not a date and the timing the model returned with it is
    # invented. That was the whole rule, and it threw away "actually 20
    # september to 22 september" -- a guest looking at a catalogue is exactly
    # the guest who notices the dates are wrong, and they were told the hotel
    # could not match that.
    #
    # A month, deliberately, and not "does the message have words in it": "3
    # nights" has words in it, and the model will happily quote them as the
    # words that say when the guest arrives. A month named in a language this
    # class cannot read is still dropped -- no better than before, and no worse.
    def message_names_a_month?
      normalized = message.downcase

      month_from_message(normalized).present? ||
        relative_month_date.present? ||
        parse_complete_date_range.present? ||
        parse_partial_day_range.present? ||
        normalized.match?(/\d{1,2}\s*月/)
    end

    def message_names_a_day?
      normalized = message.downcase
      return true if day_named_alongside_a_month?(normalized)
      return true if normalized.match?(/\b(?:tomorrow|today|tonight|next week|this weekend|next weekend|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/)
      # A bare number answering "which day?" is a day, and that is the whole of
      # what those two questions asked for.
      return true if %w[specific_timing date_range_month].include?(pending_question.to_s) && normalized.match?(/\d/)

      unspent_number?(normalized)
    end

    def day_named_alongside_a_month?(normalized)
      normalized.match?(/\b\d{1,2}(?:st|nd|rd|th)?\s+(?:#{month_pattern})\b/) ||
        normalized.match?(/\b(?:#{month_pattern})\s+\d{1,2}(?:st|nd|rd|th)?\b/) ||
        normalized.match?(/\b\d{1,2}\s*[\/-]\s*\d{1,2}(?:\s*[\/-]\s*\d{2,4})?\b/) ||
        normalized.match?(/\d{1,2}\s*[日号號]/) ||
        normalized.match?(/\b\d{1,2}(?:st|nd|rd|th)\b/)
    end

    def unspent_number?(normalized)
      normalized.gsub(/\d+\s*(?:#{counted_noun_pattern})/, " ").match?(/\d/)
    end

    def counted_noun_pattern
      @counted_noun_pattern ||= COUNTED_NOUNS.join("|")
    end

    def message_contains_month_segment?
      resolved_month_segment.present?
    end

    def explicit_timing_in_message?
      normalized = message.downcase
      return true if pending_question == "specific_timing" && message_contains_month_segment?
      return true if pending_question == "specific_timing" && parse_specific_date_answer.present?

      (message_contains_month_segment? && message_names_a_month?) ||
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
      slots["month_segment"] = resolved_month_segment.to_s
      slots.delete("check_in") unless message_names_a_day?
      slots.delete("check_out") unless explicit_checkout_in_message?
    end

    def apply_month_segment!
      slots["month_segment"] = resolved_month_segment if resolved_month_segment.present?
    end

    def resolved_month_segment
      return @resolved_month_segment if defined?(@resolved_month_segment)

      @resolved_month_segment = MonthSegmentReader.new(message).call
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

      bare_duration_answer.present? ||
        normalized.match?(/\b\d+\s*nights?\b/) ||
        normalized.match?(/\b\d+\s*days?\b/) ||
        parse_complete_date_range.present? ||
        normalized.match?(/\bstay(?:ing)?\s+for\s+\d+\s*(?:days?|nights?)\b/) ||
        normalized.match?(/\bfor\s+\d+\s*(?:days?|nights?)\b/)
    end

    # "2" answering "how many days and nights will you be staying?" is two
    # nights, the same way "2" answering the guest count is two guests.
    #
    # Without this the number says nothing the guards recognise, the duration
    # is dropped as unevidenced, and the hotel asks the same question again --
    # for as long as the guest keeps answering it the short way. Nights rather
    # than days because nights are what the search runs on, and the catalogue
    # states the stay it found back to the guest, so a wrong reading is visible
    # and can be corrected.
    def apply_duration_answer!
      return if bare_duration_answer.blank?

      slots["nights"] = bare_duration_answer
      slots.delete("days")
    end

    def bare_duration_answer
      return unless pending_question == "duration"

      @bare_duration_answer ||= message.strip[/\A(\d+)\z/, 1]&.to_i
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
    # guest said it, or the model can quote the words they said it in. Without
    # this the model's "adults: 1" on a message about nights becomes a price
    # nobody was asked to agree to.
    #
    # Having been asked is not itself evidence. This used to return true for
    # the whole of `guest_count` and `party_split` on the reasoning that the
    # hotel had just asked, so the answer must be in there -- which holds right
    # up until the guest answers "just a small one for the family". Then there
    # is no number in the message, the model supplies one anyway, and the stay
    # is priced for a party nobody ever stated. That is the one question where
    # a wrong guess is money, and it was the one question the rule was off for.
    #
    # A guest who really did answer is not caught by this: "2 adults" and a
    # bare "2" are read straight out of the message below, and an answer in any
    # other language survives on the model's quote of it -- `party_quoted?`
    # takes "dua dewasa" and "两位大人" without needing a word of English. What
    # is left over is a model filling the slot from nothing, and the ladder
    # asking again is the right answer to that.
    def party_evidence_in_message?
      explicit_people_total_in_message? ||
        explicit_adults_in_message? ||
        explicit_children_in_message?
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
