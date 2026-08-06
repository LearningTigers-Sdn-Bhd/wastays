# frozen_string_literal: true

require "bigdecimal"

module AiConcierge
  module Matching
    class RatePlanMatcher
      def initialize(message:, rate_plan_name:, rate_plans:)
        @message = message.to_s
        @rate_plan_name = rate_plan_name.to_s
        @rate_plans = Array(rate_plans)
      end

      def call
        return rate_plans.first if rate_plans.one?
        return nil if rate_plans.blank?

        normalized = normalize_rate_plan_query([ rate_plan_name, message ].reject(&:blank?).join(" "))
        return nil if normalized.blank?

        price_match = rate_plan_price_match(normalized)
        return price_match if price_match

        ordinal = rate_plan_ordinal(normalized)
        return rate_plans[ordinal] if ordinal && rate_plans[ordinal]

        refundable_match = rate_plan_refundable_match(normalized)
        return refundable_match if refundable_match

        standard_match = unique_rate_plan_match { |rate_plan| normalize_rate_plan_name(rate_plan["name"]).include?("standard") } if normalized.match?(/\bstandard\b/)
        return standard_match if standard_match

        exact_matches = rate_plans.select { |rate_plan| normalize_rate_plan_name(rate_plan["name"]) == normalized }
        return exact_matches.first if exact_matches.one?

        partial_matches = rate_plans.select do |rate_plan|
          normalized_name = normalize_rate_plan_name(rate_plan["name"])
          normalized_name.include?(normalized) || normalized.split.all? { |token| normalized_name.include?(token) }
        end
        return partial_matches.first if partial_matches.one?

        nil
      end

      private

      attr_reader :message, :rate_plan_name, :rate_plans

      def normalize_rate_plan_query(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
      end

      def normalize_rate_plan_name(value)
        normalize_rate_plan_query(value)
      end

      def rate_plan_ordinal(normalized)
        case normalized
        when /\b(?:second|two|2)\b/
          1
        when /\b(?:third|three|3)\b/
          2
        when /\b(?:first|one|1)\b/
          0
        end
      end

      def rate_plan_price_match(normalized)
        return unless normalized.match?(/\b(?:cheapest|lowest|cheaper|less expensive|lower price|lowest price)\b/)

        prices = rate_plans.filter_map { |rate_plan| BigDecimal(rate_plan["total_price"].to_s) if rate_plan["total_price"].present? }
        return if prices.empty?

        cheapest = prices.min
        matches = rate_plans.select { |rate_plan| rate_plan["total_price"].present? && BigDecimal(rate_plan["total_price"].to_s) == cheapest }
        matches.one? ? matches.first : nil
      end

      def rate_plan_refundable_match(normalized)
        if normalized.match?(/\bnon refundable\b|\bnonrefundable\b|\bno refund\b/)
          return unique_rate_plan_match { |rate_plan| normalize_rate_plan_name(rate_plan["name"]).match?(/\bnon refundable\b|\bnonrefundable\b/) }
        end

        if normalized.match?(/\brefundable\b|\bflexible\b/)
          return unique_rate_plan_match do |rate_plan|
            normalized_name = normalize_rate_plan_name(rate_plan["name"])
            normalized_name.match?(/\brefundable\b|\bflexible\b/) && !normalized_name.match?(/\bnon refundable\b|\bnonrefundable\b/)
          end
        end

        nil
      end

      def unique_rate_plan_match
        matches = rate_plans.select { |rate_plan| yield(rate_plan) }
        matches.one? ? matches.first : nil
      end
    end
  end
end
