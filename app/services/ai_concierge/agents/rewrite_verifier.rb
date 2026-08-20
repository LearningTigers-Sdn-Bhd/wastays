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
    # Room type and rate plan names are checked too, and for a different
    # reason: they are not facts the guest reads, they are words the guest is
    # about to type back. A translated "Garden Prestige Suite" is echoed in
    # translation, and matching compares it against the name in Postgres --
    # which never moved -- so the guest is told their own room does not exist.
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

      def initialize(template:, candidate:, protected_names: [])
        @template = template.to_s
        @candidate = candidate.to_s
        @protected_names = Array(protected_names).map(&:to_s).reject(&:blank?)
      end

      # The candidate when it is safe to send, nil when it is not. A caller with
      # nil sends the template, so there is nothing to raise about.
      def call
        @failure = first_failure
        failure ? nil : candidate
      end

      attr_reader :failure

      private

      attr_reader :template, :candidate, :protected_names

      def first_failure
        return :urls unless urls(template).sort == urls(candidate).sort
        return :numbers unless template.scan(NUMBER).sort == candidate.scan(NUMBER).sort
        return :currency unless currencies(template).sort == currencies(candidate).sort
        return :names unless names_kept?

        nil
      end

      # Only names the template actually used have to survive; the hotel's whole
      # catalogue is not a promise about one sentence. Case is ignored because
      # matching downcases anyway -- what must not happen is the words changing.
      def names_kept?
        haystack = candidate.downcase

        protected_names.none? do |name|
          template.downcase.include?(name.downcase) && !haystack.include?(name.downcase)
        end
      end

      # Trailing sentence punctuation is stripped from both sides rather than
      # neither: a link at the end of a line and the same link before a full
      # stop are the same link, and the guest can click either.
      def urls(text) = text.scan(URL).map { |url| url.sub(/[.,;:!?)\]]+\z/, "") }

      def currencies(text) = text.scan(PRICED_CURRENCY).flatten
    end
  end
end
