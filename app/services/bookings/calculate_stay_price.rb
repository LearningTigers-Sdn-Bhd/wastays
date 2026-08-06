# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:, rate_plan: nil, corporate_rate: false, rate_tier: :standard, pax: nil, adults: nil, children: nil, child_ages: [])
      @room_type = room_type
      @check_in = check_in&.to_date
      @check_out = check_out&.to_date
      @rate_plan = rate_plan
      @corporate_rate = corporate_rate
      @rate_tier = rate_tier.to_sym

      @adults = (adults || pax || 2).to_i
      @children = (children || 0).to_i
      @pax = @adults + @children
      ages = Array(child_ages).map(&:to_i)
      @child_ages = (ages.size == @children) ? ages : []
    end

    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      (@check_in..(@check_out - 1.day)).sum do |date|
        rate = room_rate_for(date)
        base_nightly_rate = tier_price(rate) || derived_or_fallback_rate(rate)

        Bookings::NightlyPaxPrice.call(
          base_nightly_rate: base_nightly_rate,
          rate: rate,
          rate_plan: @rate_plan,
          adults: @adults,
          children: @children,
          child_ages: @child_ages
        )
      end
    end

    private

    def tier_price(rate)
      return nil if rate.blank?

      case @rate_tier
      when :corporate then rate.corporate_price
      when :walk_in then rate.walk_in_price
      else
        @corporate_rate ? rate.corporate_price : nil
      end
    end

    def room_rate_for(date)
      scope = @room_type.room_rates.where(date: date)

      plans_to_try = [ @rate_plan, @room_type.standard_rate_plan, nil ].uniq

      plans_to_try.each do |plan|
        rate = scope.find_by(rate_plan: plan)
        return rate if rate.present?
      end

      nil
    end

    # An explicit RoomRate for @rate_plan itself always wins as-is. Otherwise
    # `rate` (if any) is the anchor Standard Rate row we fell back to in
    # room_rate_for; transform it through the rate plan's derived pricing
    # (multiplier/offset) instead of copying it verbatim.
    def derived_or_fallback_rate(rate)
      anchor = rate&.price || @room_type.base_price
      return anchor if rate.present? && rate.rate_plan_id == @rate_plan&.id

      rtrp = room_type_rate_plan
      return anchor unless rtrp&.derives_price?

      rtrp.derive_price(anchor) || anchor
    end

    def room_type_rate_plan
      return nil if @rate_plan.blank?

      @room_type_rate_plan ||= @room_type.room_type_rate_plans.find { |rtrp| rtrp.rate_plan_id == @rate_plan.id }
    end
  end
end
