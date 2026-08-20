# frozen_string_literal: true

module AiConcierge
  module Agents
    # Checks that a rewritten reply still says the same numbers as the one Ruby
    # wrote.
    #
    # The stylist is handed real money and a payable quote link, so the question
    # is not whether the words changed -- they are supposed to -- but whether
    # anything changed that the guest could act on and be wrong. Words, word
    # order and month names are free: "August 21" legitimately becomes
    # "21 Ogos". Digits, links and the currency in front of a price are not.
    #
    # Deliberately not checked: the *asterisks* around bold text and the shape
    # of an option list. Those are prompt instructions, because losing one is
    # cosmetic and losing a price is not, and a check that fails over
    # punctuation would send templates all day.
    class RewriteVerifier
      URL = %r{https?://\S+}
      NUMBER = /\d+/
      # Only a currency sitting in front of a number, which is the one shape
      # `BaseBuilder#format_price` produces. Matching bare uppercase words would
      # fail a reply over a hotel's own initials.
      PRICED_CURRENCY = /\b(RM|[A-Z]{3})\s*(?=\d)/

      def initialize(template:, candidate:)
        @template = template.to_s
        @candidate = candidate.to_s
      end

      # The candidate when it is safe to send, nil when it is not. A caller with
      # nil sends the template, so there is nothing to raise about.
      def call
        @failure = first_failure
        failure ? nil : candidate
      end

      attr_reader :failure

      private

      attr_reader :template, :candidate

      def first_failure
        return :urls unless urls(template).sort == urls(candidate).sort
        return :numbers unless template.scan(NUMBER).sort == candidate.scan(NUMBER).sort
        return :currency unless currencies(template).sort == currencies(candidate).sort

        nil
      end

      # Trailing sentence punctuation is stripped from both sides rather than
      # neither: a link at the end of a line and the same link before a full
      # stop are the same link, and the guest can click either.
      def urls(text) = text.scan(URL).map { |url| url.sub(/[.,;:!?)\]]+\z/, "") }

      def currencies(text) = text.scan(PRICED_CURRENCY).flatten
    end
  end
end
