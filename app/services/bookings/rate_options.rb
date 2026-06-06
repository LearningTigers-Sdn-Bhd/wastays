# frozen_string_literal: true

module Bookings
  class RateOptions
    def initialize(room_type:, check_in:, check_out:, apply_stop_sell: false, apply_arrival_departure: false, apply_stay_length: false)
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
      @apply_stop_sell = ActiveModel::Type::Boolean.new.cast(apply_stop_sell)
      @apply_arrival_departure = ActiveModel::Type::Boolean.new.cast(apply_arrival_departure)
      @apply_stay_length = ActiveModel::Type::Boolean.new.cast(apply_stay_length)
    end

    def call
      plans = @room_type.rate_plans.order(:name, :id).to_a
      return [ base_rate_option ] if plans.empty?

      plans.filter_map do |rate_plan|
        next if restricted?(rate_plan)

        rate_plan_option(rate_plan)
      end
    end

    def allowed?(rate_plan)
      return true if rate_plan.blank?

      !restricted?(rate_plan)
    end

    private

    def rate_plan_option(rate_plan)
      total = CalculateStayPrice.new(
        room_type: @room_type,
        rate_plan: rate_plan,
        check_in: @check_in,
        check_out: @check_out
      ).call

      {
        id: rate_plan.id,
        name: rate_plan.name,
        currency: rate_plan.currency,
        total_amount: total.to_d.to_s("F")
      }
    end

    def base_rate_option
      total = CalculateStayPrice.new(room_type: @room_type, check_in: @check_in, check_out: @check_out).call

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
      return true if @apply_arrival_departure && arrival_departure_restricted?(rates)
      return true if @apply_stay_length && stay_length_restricted?(rates)

      false
    end

    def rates_for(rate_plan)
      @room_type.room_rates.where(rate_plan: rate_plan, date: stay_dates).to_a
    end

    def arrival_departure_restricted?(rates)
      rates.find { |rate| rate.date == stay_dates.first }&.closed_to_arrival? ||
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
