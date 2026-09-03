# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Booking
      class MonthSegmentReader
        MONTH_NAME = /(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*/

        SEGMENT_PATTERNS = {
          "early" => [
            /\bearly\b/,
            /\b(?:beginning|start)(?:\s+of)?\s+(?:(?:the|this|next)\s+)?month\b/,
            /\b(?:beginning|start)(?:\s+of)?\s+#{MONTH_NAME}\b/,
            /\bawal\s+bulan\b/,
            /月初/
          ],
          "mid" => [
            /\bmid\b/,
            /\bmiddle(?:\s+of)?\s+(?:(?:the|this|next)\s+)?month\b/,
            /\bmiddle(?:\s+of)?\s+#{MONTH_NAME}\b/,
            /\bmiddle\s+part(?:\s+of\s+(?:(?:the|this|next)\s+)?month)?\b/,
            /\bpertengahan\s+bulan\b/,
            /月中/
          ],
          "late" => [
            /\blate\b/,
            /\bend(?:\s+of)?\s+(?:(?:the|this|next)\s+)?month\b/,
            /\bend(?:\s+of)?\s+#{MONTH_NAME}\b/,
            /\blast\s+part(?:\s+of\s+(?:(?:the|this|next)\s+)?month)?\b/,
            /\b(?:hujung|akhir)\s+bulan\b/,
            /月底/,
            /月末/
          ]
        }.freeze

        def initialize(message)
          @message = message.to_s.downcase.squish
        end

        def call
          matches = SEGMENT_PATTERNS.filter_map do |segment, patterns|
            segment if patterns.any? { |pattern| message.match?(pattern) }
          end

          matches.one? ? matches.first : nil
        end

        private

        attr_reader :message
      end
    end
  end
end
