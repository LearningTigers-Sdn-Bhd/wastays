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
      GUEST_CONTENT_FACTS = %w[
        arrival_instructions departure_instructions directions transportation parking
        front_desk_contact front_desk_hours emergency_contact wifi_availability
      ].freeze
      FACTS = %w[check_in_time check_out_time cancellation_policy].concat(GUEST_CONTENT_FACTS).freeze
      FACT_PATTERNS = {
        "arrival_instructions" => /\b(?:arrival|arriv(?:e|ing))\b|\b(?:how|where)\b.*\bcheck[ -]?in\b/,
        "departure_instructions" => /\b(?:departure|departing|leav(?:e|ing))\b|\b(?:how|where)\b.*\bcheck[ -]?out\b/,
        "check_in_time" => /\bcheck[ -]?in\b/,
        "check_out_time" => /\bcheck[ -]?out\b/,
        "cancellation_policy" => /\bcancell?ation|cancel\b/,
        "front_desk_hours" => /\b(?:front desk|reception)\b.*\b(?:hours?|open|close)\b|\b(?:hours?|open|close)\b.*\b(?:front desk|reception)\b/,
        "front_desk_contact" => /\b(?:front desk|reception)\b.*\b(?:contact|phone|number|call|email|whats?app|extension)\b|\b(?:contact|phone|number|call|email|whats?app)\b.*\b(?:front desk|reception)\b/,
        "emergency_contact" => /\b(?:emergency|ambulance|fire|police|security)\b/,
        "wifi_availability" => /\bwi-?fi\b|\bwireless internet\b/,
        "parking" => /\b(?:parking|car park|valet|ev charging)\b/,
        "transportation" => /\b(?:airport transfer|shuttle|public transport|transit|pickup|transport(?:ation)?)\b/,
        "directions" => /\b(?:directions?|how (?:do|can) i get|how to get|distance|far)\b/
      }.freeze

      def self.none = new

      def self.fact_for_query(query)
        normalized = query.to_s.downcase
        FACT_PATTERNS.find { |_fact, pattern| normalized.match?(pattern) }&.first
      end

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
