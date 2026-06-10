# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:, rate_plan: nil, corporate_rate: false, rate_tier: :standard)
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
      @rate_plan = rate_plan
      @corporate_rate = corporate_rate
      @rate_tier = rate_tier.to_sym
    end

    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      (@check_in..(@check_out - 1.day)).sum do |date|
        rate = room_rate_for(date)

        tier_price(rate) || rate&.price || @room_type.base_price
      end
    end

    private

    def tier_price(rate)
      return nil if rate.blank?

      case @rate_tier
      when :corporate then rate.corporate_price
      when :walk_in then rate.walk_in_price
      when :ota then rate.ota_price
      else
        @corporate_rate ? rate.corporate_price : nil
      end
    end

    def room_rate_for(date)
      scope = @room_type.room_rates.where(date: date)

      plans_to_try = [ @rate_plan, @room_type.rate_plans.first, nil ].uniq

      plans_to_try.each do |plan|
        rate = scope.find_by(rate_plan: plan)
        return rate if rate.present?
      end

      nil
    end
  end
end
