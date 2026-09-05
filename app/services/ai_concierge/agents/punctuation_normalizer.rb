# frozen_string_literal: true

module AiConcierge
  module Agents
    # Removes punctuation artifacts without changing values that the guest can act on.
    class PunctuationNormalizer
      PROTECTED_VALUE = %r{https?://\S+|\b\d+[.,]\d+\b|\b(?:RM|[A-Z]{3})\s*\d[\d,.]*}
      MALFORMED = /(?<!\d)[.!?。！？]{2,}|[.!?。！？]{2,}(?!\d)/

      def self.call(text, protected_names: [])
        new(text, protected_names: protected_names).call
      end

      def self.malformed?(text)
        text.to_s.match?(MALFORMED)
      end

      def initialize(text, protected_names: [])
        @text = text.to_s
        @protected_names = Array(protected_names).compact_blank.sort_by { |name| -name.length }
      end

      def call
        protected = []
        pattern = protection_pattern
        body = pattern ? text.gsub(pattern) { |value| token(protected, value) } : text.dup
        body = body.gsub(/(?<!\d)([.!?。！？])(?:\s*[.!?。！？])+(?!\d)/, "\\1")
        body = body.gsub(/[ \t]+([.!?。！？])/, "\\1")
        restore(body, protected)
      end

      private

      attr_reader :text, :protected_names

      def protection_pattern
        names = protected_names.map { |name| Regexp.escape(name) }
        Regexp.union(PROTECTED_VALUE, *names)
      end

      def token(values, value)
        values << value
        "\u0000#{values.length - 1}\u0000"
      end

      def restore(body, values)
        body.gsub(/\u0000(\d+)\u0000/) { values[Regexp.last_match(1).to_i] }
      end
    end
  end
end
