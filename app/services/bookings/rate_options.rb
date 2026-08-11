# frozen_string_literal: true

module Bookings
  class RateOptions
    def initialize(room_type:, check_in:, check_out:, apply_stop_sell: false, apply_arrival_departure: false, apply_stay_length: false, audience: :staff, adults: nil, children: nil, child_ages: [])
      @room_type = room_type
      @check_in = check_in.to_date
      @check_out = check_out.to_date
      @apply_stop_sell = ActiveModel::Type::Boolean.new.cast(apply_stop_sell)
      @apply_arrival_departure = ActiveModel::Type::Boolean.new.cast(apply_arrival_departure)
      @apply_stay_length = ActiveModel::Type::Boolean.new.cast(apply_stay_length)
      @audience = audience.to_sym
      # Per-person plans price off the party staying, so every option has to be
      # quoted for the same party the booking will be charged for. Omitting
      # these used to leave CalculateStayPrice on its 2-adult default while
      # BuildFinancialSnapshot charged for the real party.
      @adults = adults
      @children = children
      @child_ages = child_ages
    end

    def call
      eligible_plans.filter_map do |rate_plan|
        next if restricted?(rate_plan)
        rate_plan_option(rate_plan)
      end
    end

    def allowed?(rate_plan)
      return false if rate_plan.blank?
      return false unless rate_plan.bookable_by?(@audience)

      !restricted?(rate_plan)
    end

    private

    def occupancy
      { adults: @adults, children: @children, child_ages: @child_ages }
    end

    def rate_plan_option(rate_plan)
      total = CalculateStayPrice.new(
        room_type: @room_type,
        rate_plan: rate_plan,
        check_in: @check_in,
        check_out: @check_out,
        **occupancy
      ).call

      return if total.nil?

      {
        id: rate_plan.id,
        name: rate_plan.name,
        currency: rate_plan.currency,
        total_amount: total.to_d.to_s("F")
      }
    end

    def eligible_plans
      @room_type.rate_plans.for_audience(@audience).order(:name, :id).to_a
    end

    def restricted?(rate_plan)
      restriction_plan = @room_type.restriction_plan_for(rate_plan)
      rates = rates_for(restriction_plan)
      return true if @apply_stop_sell && rates.any?(&:stop_sell?)
      return true if @apply_arrival_departure && arrival_departure_restricted?(rates, restriction_plan)
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
