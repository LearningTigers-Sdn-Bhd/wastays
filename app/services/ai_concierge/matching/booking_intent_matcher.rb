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
        return true if normalized.match?(/\b(?:cheapest|lowest)\b/) && normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stay|stays|night|nights)\b/)

        normalized.match?(/\b(?:rates?|prices?|pricing|cost)\b/) && normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stay|stays|night|nights)\b/)
      end

      # These words state commitment. Price words without one of these words
      # mean that the guest is still comparing options.
      def booking_commitment?
        normalized.match?(/\b(?:book|reserve|continue|proceed)\b/)
      end

      # Price shopping crosses into booking only when the guest names the
      # purchase action. General progress words do not give that consent.
      def explicit_purchase_commitment?
        normalized.match?(/\b(?:book|reserve)\b/) ||
          normalized.match?(/\b(?:make|start|create)\s+(?:a\s+)?(?:booking|reservation)\b/)
      end

      # "How do I book?" is a question before it is a booking request.
      #
      # The ladder still opens -- the honest answer is that they book here,
      # with the first question -- but a reply that only asks for a date has
      # walked past what the guest actually said.
      HOW_TO_TOKENS = /\b(?:how|can|could|may|where)\b/

      def how_to_question?
        return false unless booking?

        normalized.match?(HOW_TO_TOKENS)
      end

      private

      attr_reader :message

      def normalized
        @normalized ||= message.downcase.gsub(/[^a-z0-9]+/, " ").squish
      end
    end
  end
end
