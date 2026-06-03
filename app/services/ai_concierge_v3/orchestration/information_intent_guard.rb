module AiConciergeV3
  module Orchestration
    class InformationIntentGuard
    def initialize(message:, interpretation:)
      @message = message.to_s
      @interpretation = interpretation
    end

    def call
      return policy_interpretation if policy_question?
      return interpretation if clear_booking_request?
      return interpretation unless hotel_knowledge_question?

      interpretation.deep_dup.tap do |guarded|
        guarded["intent"] = "hotel_information"
        guarded["topic"] = "general_hotel_info"
        guarded["slots"] ||= {}
        guarded["slots"]["room_type_name"] = nil
        guarded["tool_hints"] = [ "get_general_hotel_info" ]
      end
    end

    private

    attr_reader :message, :interpretation

    def policy_question?
      normalized = normalize_text(message)

      normalized.match?(/\b(?:policy|policies|rules?|house rules?|hotel rules?|cancell?ation|check in|check out)\b/) ||
        booking_advice_question?(normalized)
    end

    def booking_advice_question?(normalized)
      normalized.match?(/\bbooking\b/) &&
        normalized.match?(/\b(?:aware|know|notice|note|terms?|conditions?|requirements?|important|before|during|while|when)\b/)
    end

    def policy_interpretation
      interpretation.deep_dup.tap do |guarded|
        guarded["intent"] = "hotel_policy"
        guarded["topic"] = "hotel_policy"
        guarded["slots"] ||= {}
        guarded["tool_hints"] = [ "get_hotel_policy" ]
      end
    end

    def clear_booking_request?
      normalized = normalize_text(message)
      return true if normalized.match?(/\b(?:book|booking|reserve|reservation|quote)\b/)
      return true if normalized.match?(/\b(?:availability|available)\b/) && room_or_stay_reference?(normalized)

      room_or_stay_reference?(normalized) && timing_reference?(normalized)
    end

    def hotel_knowledge_question?
      normalized = normalize_text(message)
      return false if room_scoped_question?(normalized)
      return true if hotel_amenities_question?(normalized)
      return true if hotel_service_question?(normalized)

      normalized.match?(/\b(?:do you have|does (?:the )?hotel provide|is there|are there|is .* available|may i know|can i know|could i know)\b/) &&
        normalized.match?(/\b(?:wifi|wi fi|breakfast|parking|transport|transportation|transfer|shuttle|pickup|pick up|drop off|restaurant|spa|pool|facility|facilities|amenity|amenities)\b/)
    end

    def hotel_amenities_question?(normalized = normalize_text(message))
      return false unless normalized.match?(/\b(amenit(?:y|ies)|facilit(?:y|ies))\b/)

      !room_scoped_question?(normalized) || normalized.match?(/\b(hotel|property)\b/)
    end

    def hotel_service_question?(normalized)
      normalized.match?(/\b(?:parking|transport|transportation|airport transfer|transfer|shuttle|pickup|pick up|drop off|wifi|wi fi|breakfast|restaurant|spa|pool)\b/)
    end

    def room_scoped_question?(normalized)
      normalized.match?(/\b(room|suite|villa|penthouse|deluxe|executive|standard|superior|family)\b/)
    end

    def room_or_stay_reference?(normalized)
      normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stay|stays|night|nights)\b/)
    end

    def timing_reference?(normalized)
      normalized.match?(/\b(?:today|tomorrow|tonight|this month|next month|early|mid|late|jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b/) ||
        normalized.match?(/\b\d{1,2}(?:st|nd|rd|th)?\b/)
    end

    def normalize_text(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
    end
  end
end
