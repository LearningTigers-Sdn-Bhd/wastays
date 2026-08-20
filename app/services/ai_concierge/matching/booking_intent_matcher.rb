# frozen_string_literal: true

module AiConcierge
  module Matching
    # Is this message about booking a stay?
    #
    # Used as a backstop, not a router: the model picks the tool, and this only
    # speaks up when the model picked nothing at all. "Can I make a booking"
    # carries no slots, so a model looking for something to extract can decide
    # no tool fits and answer in its own words -- which is how a guest gets
    # asked for a room type they have no way of knowing.
    class BookingIntentMatcher
      # Words that make a message about the rules of a stay rather than the
      # buying of one. "Can I cancel my booking" says booking and means policy.
      POLICY_TOKENS = /\b(?:cancel|cancellation|refund|refunds|policy|policies)\b/

      def initialize(message:)
        @message = message.to_s
      end

      def booking?
        return false if normalized.blank?
        return false if normalized.match?(POLICY_TOKENS)
        return true if rate_question?

        normalized.match?(/\b(?:book|booking|bookings|reserve|reserving|reservation|reservations)\b/) ||
          normalized.match?(/\b(?:availability|available|vacancy|vacancies)\b/) ||
          normalized.match?(/\b(?:quote|quotation)\b/)
      end

      # Kept distinct because the booking ladder opens with a different
      # sentence when the guest asked what a room costs.
      def rate_question?
        return false if normalized.match?(/\broom service\b/)

        return true if normalized.match?(/\brooms?\s+(?:rates?|prices?|pricing|cost)\b/)
        return true if normalized.match?(/\b(?:rates?|prices?|pricing|cost)\s+(?:for|of)\s+(?:a\s+)?rooms?\b/)
        return true if normalized.match?(/\bhow much\b/) && normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stay|stays|night|nights)\b/)

        normalized.match?(/\b(?:rates?|prices?|pricing|cost)\b/) && normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stay|stays|night|nights)\b/)
      end

      private

      attr_reader :message

      def normalized
        @normalized ||= message.downcase.gsub(/[^a-z0-9]+/, " ").squish
      end
    end
  end
end
