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
      return false unless rate_plan.day_use? == day_use_stay?

      !restricted?(rate_plan)
    end

    # Why the enabled restrictions refuse this plan for these dates, in words a
    # booker can act on, or nil when none do.
    def restriction_reason(rate_plan)
      restriction_plan = @room_type.restriction_plan_for(rate_plan)
      rates = rates_for(restriction_plan)

      (@apply_stop_sell && stop_sell_reason(rates)) ||
        (@apply_arrival_departure && arrival_departure_reason(rates, restriction_plan)) ||
        (@apply_stay_length && !day_use_stay? && stay_length_reason(rates)) ||
        nil
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
        day_use_hours: rate_plan.day_use_hours,
        currency: rate_plan.currency,
        total_amount: total.to_d.to_s("F")
      }
    end

    def eligible_plans
      @room_type.rate_plans.for_audience(@audience).where(day_use_hours: day_use_stay? ? 1..24 : nil).order(:name, :id).to_a
    end

    def day_use_stay?
      @check_in == @check_out
    end

    def restricted?(rate_plan)
      restriction_reason(rate_plan).present?
    end

    def rates_for(rate_plan)
      @room_type.room_rates.where(rate_plan: rate_plan, date: stay_dates).to_a
    end

    def stop_sell_reason(rates)
      closed = rates.select(&:stop_sell?).map(&:date).sort
      "Closed for sale on #{closed.map { |date| format_date(date) }.to_sentence}" if closed.any?
    end

    def arrival_departure_reason(rates, rate_plan)
      return "No arrivals on #{format_date(@check_in)}" if rates.find { |rate| rate.date == @check_in }&.closed_to_arrival?

      return if day_use_stay?

      checkout_rate = @room_type.room_rates.find_by(rate_plan: rate_plan, date: @check_out)
      return "No departures on #{format_date(@check_out)}" if checkout_rate&.closed_to_departure?

      "No departures on #{format_date(@check_out)}" if rates.find { |rate| rate.date == stay_dates.last }&.closed_to_departure?
    end

    def stay_length_reason(rates)
      min_stay = rates.filter_map(&:min_stay).select { |value| nights < value }.max
      return "Minimum stay #{min_stay} nights" if min_stay

      max_stay = rates.filter_map(&:max_stay).select { |value| nights > value }.min
      "Maximum stay #{max_stay} #{'night'.pluralize(max_stay)}" if max_stay
    end

    def format_date(date) = date.strftime("%-d %b")

    def stay_dates
      @stay_dates ||= ScheduledStay.billable_dates(@check_in, @check_out)
    end

    def nights
      @nights ||= stay_dates.size
    end
  end
end
