# frozen_string_literal: true

module AiConcierge
  module Retrieval
    # What the model can tell us about a question that Ruby cannot work out for
    # itself, once the question stops being in English.
    #
    # Keyword search is where exact names live -- a room type, a wifi SSID, a
    # dish on the menu -- which is the thing vector search is worst at. It
    # matches words, so a Chinese question against a Malay document shares
    # nothing to match and it contributes nothing. `terms` is the model handing
    # over the same question in the languages the hotel actually wrote its
    # documents in, so there is something to match again.
    #
    # `fact` is the other half: check-in time, check-out time and the
    # cancellation policy are answered from Postgres without searching at all,
    # and that -- the fastest and most certain answer the concierge has -- used
    # to be reachable only by matching English words in the question.
    class QueryHints
      FACTS = %w[check_in_time check_out_time cancellation_policy].freeze

      def self.none = new

      def initialize(terms: [], fact: nil, preferred_language: nil)
        @terms = Array(terms).flat_map { |term| term.to_s.split }.reject(&:blank?).uniq
        @fact = fact.to_s.presence_in(FACTS)
        @preferred_language = preferred_language.to_s.presence
      end

      attr_reader :terms, :fact, :preferred_language

      # Two questions that hint differently are two questions, so the answer
      # cache has to be able to tell them apart.
      def digest = [ terms.sort, fact, preferred_language ]

      def to_h = { "terms" => terms, "fact" => fact, "preferred_language" => preferred_language }

      def self.from(value)
        return value if value.is_a?(self)
        return none unless value.is_a?(Hash)

        hash = value.symbolize_keys
        new(terms: hash[:terms], fact: hash[:fact], preferred_language: hash[:preferred_language])
      end
    end
  end
end
