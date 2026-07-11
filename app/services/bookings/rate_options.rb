# frozen_string_literal: true

module Bookings
  class RateOptions
    def initialize(room_type:, check_in:, check_out:, apply_stop_sell: false, apply_arrival_departure: false, apply_stay_length: false, corporate_rate: false)
      @room_type = room_type
      @check_in = check_in.to_date
      @check_out = check_out.to_date
      @apply_stop_sell = ActiveModel::Type::Boolean.new.cast(apply_stop_sell)
      @apply_arrival_departure = ActiveModel::Type::Boolean.new.cast(apply_arrival_departure)
      @apply_stay_length = ActiveModel::Type::Boolean.new.cast(apply_stay_length)
      @corporate_rate = ActiveModel::Type::Boolean.new.cast(corporate_rate)
    end

    def call
      all_plans = @room_type.rate_plans.order(:name, :id).to_a
      return [ base_rate_option ] if all_plans.empty?

      # Filter out plans that are actually special tiers
      standard_plans = all_plans.reject(&:special_tier?)

      options = standard_plans.filter_map do |rate_plan|
        next if restricted?(rate_plan)
        rate_plan_option(rate_plan)
      end

      # Add virtual tiers if they exist on the standard plan (usually the first one)
      standard_plan = all_plans.first
      if standard_plan
        options << tier_option(standard_plan, :walk_in, "Walk-in Rate") if has_tier_price?(standard_plan, :walk_in)
      end

      options
    end

    def allowed?(rate_plan)
      return true if rate_plan.blank?
      return true if rate_plan.special_tier? # Tiers are handled via standard plan restrictions

      !restricted?(rate_plan)
    end

    private

    def tier_option(rate_plan, tier, label)
      total = CalculateStayPrice.new(
        room_type: @room_type,
        rate_plan: rate_plan,
        check_in: @check_in,
        check_out: @check_out,
        rate_tier: tier,
        corporate_rate: @corporate_rate
      ).call

      {
        id: "tier_#{tier}_#{@room_type.id}", # Match virtual ID format: tier_[tier_type]_[room_type_id]
        name: label,
        currency: rate_plan.currency,
        total_amount: total.to_d.to_s("F"),
        is_tier: true,
        tier_kind: tier,
        base_rate_plan_id: rate_plan.id
      }
    end

    def has_tier_price?(rate_plan, tier)
      # Check if any date in the window has an override for this tier
      column = case tier.to_sym
      when :walk_in then "walk_in_price"
      when :corporate then "corporate_price"
      end

      return false if column.blank?

      rate_plan.room_rates.where(date: stay_dates).where.not(column => nil).exists?
    end

    def rate_plan_option(rate_plan)
      total = CalculateStayPrice.new(
        room_type: @room_type,
        rate_plan: rate_plan,
        check_in: @check_in,
        check_out: @check_out,
        rate_tier: rate_plan.special_tier_kind || :standard,
        corporate_rate: @corporate_rate
      ).call

      {
        id: rate_plan.id,
        name: rate_plan.name,
        currency: rate_plan.currency,
        total_amount: total.to_d.to_s("F")
      }
    end

    def base_rate_option
      total = CalculateStayPrice.new(
        room_type: @room_type,
        check_in: @check_in,
        check_out: @check_out,
        corporate_rate: @corporate_rate
      ).call

      {
        id: nil,
        name: "Base Rate",
        currency: @room_type.hotel.default_currency.presence || "MYR",
        total_amount: total.to_d.to_s("F")
      }
    end

    def restricted?(rate_plan)
      rates = rates_for(rate_plan)
      return true if @apply_stop_sell && rates.any?(&:stop_sell?)
      return true if @apply_arrival_departure && arrival_departure_restricted?(rates, rate_plan)
      return true if @apply_stay_length && stay_length_restricted?(rates)

      false
    end

    def rates_for(rate_plan)
      @room_type.room_rates.where(rate_plan: rate_plan, date: stay_dates).to_a
    end

    def arrival_departure_restricted?(rates, rate_plan)
      return true if rates.find { |rate| rate.date == @check_in }&.closed_to_arrival?

      checkout_rate = @room_type.room_rates.find_by(rate_plan: rate_plan, date: @check_out)
      return true if checkout_rate&.closed_to_departure?

      rates.find { |rate| rate.date == stay_dates.last }&.closed_to_departure?
    end

    def stay_length_restricted?(rates)
      rates.any? { |rate| rate.min_stay.present? && nights < rate.min_stay } ||
        rates.any? { |rate| rate.max_stay.present? && nights > rate.max_stay }
    end

    def stay_dates
      @stay_dates ||= (@check_in...@check_out).to_a
    end

    def nights
      @nights ||= stay_dates.size
    end
  end
end
