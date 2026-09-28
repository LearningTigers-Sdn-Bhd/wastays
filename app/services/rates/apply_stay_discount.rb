# frozen_string_literal: true

module Rates
  # Applies a rate plan's long-stay discount to the nights of one stay.
  #
  # The longest rule the stay qualifies for wins (a 5-night stay under "2+
  # nights 10%" and "4+ nights 20%" gets 20%). It works on whole stays, never a
  # single night, because what a night costs depends on how long the stay is --
  # which is why it sits beside ResolveEffectiveNightlyPrice rather than inside
  # it. Direct channels only: the channel manager never sees these prices.
  #
  # Each discounted night keeps its pre-discount price and the rule applied, so
  # invoices and reports can explain the figure, and so a snapshot that has
  # already been discounted (a frozen quote becoming a booking) is never
  # discounted a second time.
  class ApplyStayDiscount
    def self.rule_for(rate_plan, nights)
      return if rate_plan.blank? || nights.to_i < 2

      rules = if rate_plan.association(:rate_plan_stay_discounts).loaded?
        rate_plan.rate_plan_stay_discounts
      else
        rate_plan.rate_plan_stay_discounts.to_a
      end
      rules.select { |rule| rule.min_nights <= nights.to_i }.max_by(&:min_nights)
    end

    # Ordered nightly prices in, discounted nightly prices out.
    def self.amounts(rate_plan:, amounts:, guests: 1)
      rule = rule_for(rate_plan, amounts.size)
      return amounts.map(&:to_d) if rule.blank?

      amounts.each_with_index.map { |price, index| rule.apply(price, night_number: index + 1, guests: guests) }
    end

    # A nightly snapshot keyed by ISO date, as BuildFinancialSnapshot and the
    # booking engine produce it. Returns a new hash; the input is not changed.
    def self.snapshot(rate_plan:, snapshot:, guests: 1)
      nights = snapshot.keys.sort
      rule = rule_for(rate_plan, nights.size)
      return snapshot if rule.blank?

      nights.each_with_index.to_h do |date, index|
        night = snapshot[date].to_h.stringify_keys
        next [ date, night ] if night.key?("undiscounted_price")

        discounted = rule.apply(night["price"], night_number: index + 1, guests: guests)
        next [ date, night ] if discounted == night["price"].to_d

        [ date, night.merge(
          "price" => discounted.to_s("F"),
          "undiscounted_price" => night["price"].to_d.to_s("F"),
          "stay_discount" => { "rule_id" => rule.id, "min_nights" => rule.min_nights, "discount_type" => rule.discount_type,
                               "value" => rule.value.to_d.to_s("F"), "from_night" => rule.from_night }
        ) ]
      end
    end

    # Who an amount-off rule counts: every guest on a per-person plan, the room
    # otherwise.
    def self.guests_for(rate_plan, adults:, children:)
      rate_plan&.sell_mode == "per_person" ? [ adults.to_i + children.to_i, 1 ].max : 1
    end
  end
end
