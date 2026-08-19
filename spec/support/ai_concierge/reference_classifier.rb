# frozen_string_literal: true

# The one place a guest message becomes an interpretation in tests.
#
# Twelve spec files each defined their own `interpretation(...)` helper, and two
# request specs carried a private regex router that reached into the agent's
# instance variables. All of them approximated the same thing: what the model
# would have said about this message.
#
# This says it once, and says it *compositionally* -- every signal the sentence
# states is extracted, instead of the first matching rule winning and the rest
# of the sentence being thrown away. A guest who writes "early august, 3 days 2
# nights, 2 adults" states four things, and a classifier that returns only the
# first is not modelling a language model.
module AiConciergeEval
  class ReferenceClassifier
    MONTHS = Date::MONTHNAMES.compact.each_with_index.to_h { |name, index| [ name.downcase, index + 1 ] }.freeze
    MONTH_ABBREVIATIONS = Date::ABBR_MONTHNAMES.compact.each_with_index.to_h { |name, index| [ name.downcase, index + 1 ] }.freeze
    MONTH_PATTERN = (MONTHS.keys + MONTH_ABBREVIATIONS.keys).join("|")
    SEGMENTS = %w[early mid late].freeze

    DEFAULT_SIGNALS = {
      "is_reset" => false,
      "is_resume" => false,
      "is_correction" => false,
      "starts_new_booking_branch" => false,
      "end_conversation" => false
    }.freeze

    def self.call(...) = new(...).call

    def initialize(message:, conversation_summary: {}, today: Date.current)
      @message = message.to_s
      @normalized = @message.downcase.gsub(/[^a-z0-9]+/, " ").squish
      @conversation_summary = conversation_summary || {}
      @today = today
    end

    def call
      slots = booking_slots
      {
        "message_type" => message_type(slots),
        "intent" => intent(slots),
        "topic" => topic(slots),
        "confidence" => 1.0,
        "slots" => slots,
        "tool_hints" => [],
        "conversation_signals" => DEFAULT_SIGNALS.merge(signals)
      }
    end

    private

    attr_reader :message, :normalized, :conversation_summary, :today

    # --- intent -------------------------------------------------------------
    #
    # Information intents are checked before booking ones, mirroring
    # TransitionPolicy: a guest mid-booking who asks about parking is asking
    # about parking.

    def intent(slots)
      return "reset" if reset?
      return "hotel_policy" if policy?
      return "nearby_attractions" if attractions?
      return "hotel_information" if hotel_information?
      return "room_information" if room_information?
      return "booking_context" if existing_booking?
      return "confirmation" if slots.key?("confirmation")
      return "option_selection" if slots.key?("option_number")
      return "booking_search" if booking?(slots)

      "greeting"
    end

    def topic(slots)
      case intent(slots)
      when "hotel_policy" then "hotel_policy"
      when "nearby_attractions" then "nearby_attractions"
      when "hotel_information" then faq? ? "hotel_faq" : "general_hotel_info"
      when "room_information" then "room_information"
      when "booking_context" then "booking_context"
      when "booking_search", "confirmation", "option_selection" then "booking_search"
      else "general"
      end
    end

    def message_type(slots)
      case intent(slots)
      when "hotel_policy" then "hotel_policy_question"
      when "hotel_information", "nearby_attractions" then "hotel_info_question"
      when "room_information" then "room_info_question"
      when "booking_context" then "existing_booking_question"
      when "confirmation" then "booking_confirmation"
      when "option_selection" then "booking_selection"
      when "reset" then "conversation_control"
      when "booking_search" then "booking_request"
      else "greeting_or_unknown"
      end
    end

    def signals
      {
        "is_reset" => reset?,
        "starts_new_booking_branch" => normalized.match?(/\banother (?:booking|reservation)\b/),
        "end_conversation" => normalized.match?(/\A(?:stop|bye|goodbye|thanks|thank you|nevermind|never mind|end chat)\z/)
      }
    end

    # --- topic predicates ---------------------------------------------------

    def reset? = normalized.match?(/\b(?:reset|start over|start again)\b/)

    def policy?
      return true if normalized.match?(/\b(?:polic(?:y|ies)|rules?|house rules?|cancell?ation)\b/)
      return true if normalized.match?(/\bcheck (?:in|out)\b/) && !booking_verb?

      # "what should I be aware of when booking" is a question about terms,
      # not an attempt to book.
      normalized.match?(/\bbooking\b/) &&
        normalized.match?(/\b(?:aware|know|notice|note|terms?|conditions?|requirements?|important|before|during)\b/)
    end

    def attractions? = normalized.match?(/\b(?:attractions?|nearby|nearest|places? to (?:go|visit|eat))\b/)

    def faq? = normalized.match?(/\bfaqs?\b/)

    def hotel_information?
      return true if faq?
      return true if normalized.match?(/\btell me about the (?:hotel|property)\b/)
      return true if amenities? && !room_scoped?
      return true if service_words? && !room_scoped?

      false
    end

    def room_information?
      return false unless room_scoped?
      return false if rate_question?

      normalized.match?(/\b(?:tell me about|details? (?:for|of|about)|about the|describe|what(?:'s| is) in)\b/) ||
        (amenities? && room_scoped?)
    end

    def existing_booking? = normalized.match?(/\b(?:my|existing|current) (?:booking|reservation|stay)\b/)

    # A price question about a room is an attempt to book, not a request for
    # published information -- rates depend on dates, so the answer is a quote.
    # "room service" is never a room question, which is why it is excluded
    # everywhere `room` is matched.
    def rate_question?
      return false if room_service?

      normalized.match?(/\b(?:rates?|prices?|pricing|cost|how much)\b/) && room_or_stay?
    end

    def booking?(slots)
      return true if booking_verb?
      return true if rate_question?
      return true if normalized.match?(/\b(?:availability|available)\b/) && room_or_stay?

      slots.except("room_type_name").any?
    end

    def booking_verb? = normalized.match?(/\b(?:book|booking|reserve|reservation|quote)\b/)

    def room_service? = normalized.match?(/\broom service\b/)

    def room_scoped?
      return false if room_service?

      normalized.match?(/\b(?:rooms?|suite|villa|penthouse|deluxe|executive|standard|superior|family|garden|ocean)\b/)
    end

    def room_or_stay? = normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stays?|nights?)\b/)

    def amenities? = normalized.match?(/\b(?:amenit(?:y|ies)|facilit(?:y|ies))\b/)

    def service_words?
      normalized.match?(/\b(?:wifi|wi fi|breakfast|parking|transport|transportation|transfer|shuttle|pickup|pick up|drop off|restaurant|spa|pool|room service)\b/)
    end

    # --- slots --------------------------------------------------------------

    def booking_slots
      {}.merge(confirmation_slot, option_slot, date_slots, duration_slots, party_slots, room_type_slot)
    end

    def confirmation_slot
      return { "confirmation" => "yes" } if normalized.match?(/\A(?:yes|yeah|yep|sure|ok|okay|confirm|correct)\z/)
      return { "confirmation" => "no" } if normalized.match?(/\A(?:no|nope|not really)\z/)

      {}
    end

    def option_slot
      number = normalized[/\boption (\d+)\b/, 1]
      number ? { "option_number" => number } : {}
    end

    # "august 3 days 2 nights" states a month and a duration, not the 3rd of
    # August -- so a number that belongs to a following noun is not a day.
    COUNTED_NOUNS = "days?|nights?|adults?|child|children|kids?|people|persons?|pax|guests?|rooms?"

    def date_slots
      if (match = normalized.match(/\b(#{MONTH_PATTERN}) (\d{1,2})\b(?! (?:#{COUNTED_NOUNS}))/)) ||
         (match = normalized.match(/\b(\d{1,2}) (#{MONTH_PATTERN})\b/))
        name, day = match[1].match?(/\d/) ? [ match[2], match[1] ] : [ match[1], match[2] ]
        month = month_number(name)
        return { "check_in" => Date.new(year_for(month), month, day.to_i).iso8601 } if month
      end

      month = normalized[/\b(#{MONTH_PATTERN})\b/, 1]
      return {} unless month

      number = month_number(month)
      slots = { "target_month" => number, "target_year" => year_for(number) }
      segment = SEGMENTS.find { |candidate| normalized.match?(/\b#{candidate}\b/) }
      segment ? slots.merge("month_segment" => segment) : slots
    end

    def duration_slots
      slots = {}
      slots["days"] = Regexp.last_match(1).to_i if normalized.match(/\b(\d+) days?\b/)
      slots["nights"] = Regexp.last_match(1).to_i if normalized.match(/\b(\d+) nights?\b/)
      slots
    end

    def party_slots
      slots = {}
      slots["adults"] = Regexp.last_match(1).to_i if normalized.match(/\b(\d+) adults?\b/)
      slots["children"] = Regexp.last_match(1).to_i if normalized.match(/\b(\d+) (?:child|children|kids?)\b/)
      slots["room_count"] = Regexp.last_match(1).to_i if normalized.match(/\b(\d+) rooms?\b/)
      slots["party_size_total"] = Regexp.last_match(1).to_i if normalized.match(/\b(\d+) (?:people|persons?|pax|guests?)\b/)
      slots
    end

    # Only a room type the hotel actually has can be a slot value, so the
    # fixture's own seeded rooms are the vocabulary.
    def room_type_slot
      name = Array(conversation_summary["room_type_names"]).find do |candidate|
        normalized.include?(candidate.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish)
      end
      name ? { "room_type_name" => name } : {}
    end

    def month_number(name) = MONTHS[name] || MONTH_ABBREVIATIONS[name]

    def year_for(month)
      candidate = Date.new(today.year, month, 1)
      candidate < today.beginning_of_month ? today.year + 1 : today.year
    end
  end
end
