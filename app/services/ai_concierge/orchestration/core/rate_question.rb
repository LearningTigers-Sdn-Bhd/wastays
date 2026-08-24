# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Core
      # "How much is a room?" is an attempt to book.
      #
      # Rates depend on dates, so the honest answer is a quote, not a page from
      # the brochure. This is the one rule out of InformationIntentGuard's
      # hundred and fifty lines that is kept, because it is the one that costs
      # money to get wrong: a guest asking the price at 11pm and being handed a
      # room description instead of a booking is the entire business case for
      # the concierge, missed.
      #
      # It lives here rather than ahead of the model, and is applied by the
      # tools that would otherwise answer -- a tool declining work that is not
      # its own, rather than a policy second-guessing a classification.
      #
      # "Room service" is excluded deliberately: it contains the word room and
      # is never a room.
      class RateQuestion
        def initialize(message:)
          @normalized = message.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
        end

        def call
          return false if room_service?

          return true if normalized.match?(/\brooms?\s+(?:rates?|prices?|pricing|cost)\b/)
          return true if normalized.match?(/\b(?:rates?|prices?|pricing|cost)\s+(?:for|of)\s+(?:a\s+)?rooms?\b/)
          return true if normalized.match?(/\bhow much\b/) && room_or_stay?

          normalized.match?(/\b(?:rates?|prices?|pricing|cost)\b/) && room_or_stay?
        end

        private

        attr_reader :normalized

        def room_service? = normalized.match?(/\broom service\b/)

        def room_or_stay?
          normalized.match?(/\b(?:rooms?|suite|villa|penthouse|stays?|nights?)\b/)
        end
      end
    end
  end
end
