module AiConciergeV3
  module Orchestration
    class InformationIntentGuard
    def initialize(message:, interpretation:)
      @message = message.to_s
      @interpretation = interpretation
    end

    def call
      return policy_interpretation if policy_question?
      return interpretation unless hotel_amenities_question?

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

      normalized.match?(/\b(?:policy|policies|rules?|cancell?ation|check in|check out)\b/)
    end

    def policy_interpretation
      interpretation.deep_dup.tap do |guarded|
        guarded["intent"] = "hotel_policy"
        guarded["topic"] = "hotel_policy"
        guarded["slots"] ||= {}
        guarded["tool_hints"] = [ "get_hotel_policy" ]
      end
    end

    def hotel_amenities_question?
      normalized = normalize_text(message)
      return false unless normalized.match?(/\b(amenit(?:y|ies)|facilit(?:y|ies))\b/)

      !normalized.match?(/\b(room|suite|villa|penthouse|deluxe|executive|standard|superior|family)\b/) || normalized.match?(/\b(hotel|property)\b/)
    end

    def normalize_text(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
    end
  end
end
