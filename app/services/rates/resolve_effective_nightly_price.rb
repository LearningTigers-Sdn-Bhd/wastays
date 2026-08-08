# frozen_string_literal: true

module Rates
  class ResolveEffectiveNightlyPrice
    # occupancy_priced distinguishes the two things base_amount can be: the room
    # total for the requested adults (an occupancy matrix supplied it), or the
    # per-adult figure the caller still has to multiply (no matrix). Callers
    # that display base_amount cannot tell those apart from `source` — both
    # paths report daily_override/starting_price/standard_daily_rate — and the
    # calendar was labelling the per-adult figure as an occupancy total.
    Result = Data.define(:amount, :base_amount, :currency, :source, :room_rate, :occupancy_priced)

    def self.call(...)
      new(...).call
    end

    def initialize(
      room_type:,
      rate_plan:,
      date:,
      currency: nil,
      adults: 2,
      children: 0,
      child_ages: [],
      rate_tier: :standard,
      room_rates: nil,
      room_type_rate_plan: nil
    )
      @room_type = room_type
      @rate_plan = rate_plan
      @date = date.to_date
      @currency = CurrencyCatalog.normalize(currency, fallback: default_currency)
      @adults = adults.to_i
      @children = children.to_i
      @child_ages = child_ages
      @rate_tier = rate_tier.to_sym
      @room_rates = room_rates
      @supplied_room_type_rate_plan = room_type_rate_plan
    end

    def call
      occupancy_amount, occupancy_source, occupancy_room_rate = resolve_occupancy_amount
      base_amount, source, price_rate = resolve_base_amount
      if base_amount.nil?
        return Result.new(amount: nil, base_amount: nil, currency: @currency, source: nil, room_rate: price_rate, occupancy_priced: false)
      end

      if matrix_configured? && occupancy_amount.nil?
        return Result.new(amount: nil, base_amount: nil, currency: @currency, source: nil, room_rate: occupancy_room_rate, occupancy_priced: false)
      end

      child_anchor = if occupancy_amount.present? && @adults.positive?
        occupancy_amount / @adults
      else
        base_amount
      end

      amount = Bookings::NightlyPaxPrice.call(
        base_nightly_rate: child_anchor,
        rate: occupancy_rate,
        rate_plan: @rate_plan,
        adults: @adults,
        children: @children,
        child_ages: @child_ages,
        adult_occupancy_price: occupancy_amount
      )

      Result.new(
        amount: amount,
        base_amount: occupancy_amount || base_amount,
        currency: @currency,
        source: occupancy_source || source,
        room_rate: occupancy_room_rate || price_rate,
        occupancy_priced: occupancy_amount.present?
      )
    end

    private

    def resolve_occupancy_amount
      return [ nil, nil, nil ] unless @rate_plan&.sell_mode == "per_person" && @adults.positive?

      daily_price = selected_rate&.occupancy_prices&.fetch(@adults.to_s, nil)
      return [ daily_price.to_d, :daily_override, selected_rate ] if daily_price.present?

      starting_price = room_type_rate_plan&.occupancy_price_for(@adults)
      return [ starting_price, :starting_price, nil ] if starting_price.present?

      if room_type_rate_plan&.derives_price?
        anchor = anchor_rate&.occupancy_prices&.fetch(@adults.to_s, nil)
        anchor ||= standard_assignment&.occupancy_price_for(@adults)
        return [ room_type_rate_plan.derive_price(anchor), anchor_rate.present? ? :standard_daily_rate : :starting_price, anchor_rate ] if anchor.present?
      end

      [ nil, nil, selected_rate ]
    end

    def matrix_configured?
      return false unless @rate_plan&.sell_mode == "per_person"

      selected_rate&.occupancy_prices.present? ||
        room_type_rate_plan&.occupancy_prices&.any? ||
        standard_assignment&.occupancy_prices&.any?
    end

    def resolve_base_amount
      if tier_price.present?
        return [ tier_price, :daily_override, selected_rate || anchor_rate ]
      end

      if selected_rate.present?
        source = selected_rate.rate_plan_id == standard_rate_plan&.id ? :standard_daily_rate : :daily_override
        return [ selected_rate.price, source, selected_rate ]
      end

      assignment = room_type_rate_plan
      if assignment&.pricing_mode == "fixed"
        return [ assignment.pricing_value, :starting_price, nil ] if assignment.pricing_value.present?
        return [ @room_type.base_price, :room_category_default, nil ] unless @rate_plan&.standard_rate?
      end

      anchor = anchor_rate&.price || @room_type.base_price
      return [ nil, nil, anchor_rate ] if anchor.nil?

      if assignment&.derives_price?
        return [ assignment.derive_price(anchor) || anchor, anchor_source, anchor_rate ]
      end

      [ anchor, anchor_source, anchor_rate ]
    end

    def tier_price
      rate = selected_rate || anchor_rate

      case @rate_tier
      when :walk_in then rate&.walk_in_price
      when :corporate then rate&.corporate_price
      end
    end

    def selected_rate
      @selected_rate ||= begin
        plan_id = @rate_plan&.id
        find_rate(plan_id) || (find_rate(nil) if @rate_plan.nil?)
      end
    end

    def anchor_rate
      @anchor_rate ||= begin
        standard_id = standard_rate_plan&.id
        rate = find_rate(standard_id) if standard_id.present?
        rate || find_rate(nil)
      end
    end

    def occupancy_rate
      selected_rate
    end

    def standard_assignment
      return if standard_rate_plan.blank?

      @standard_assignment ||= if @room_type.association(:room_type_rate_plans).loaded?
        @room_type.room_type_rate_plans.find { |assignment| assignment.rate_plan_id == standard_rate_plan.id }
      else
        @room_type.room_type_rate_plans.find_by(rate_plan_id: standard_rate_plan.id)
      end
    end

    def anchor_source
      anchor_rate.present? ? :standard_daily_rate : :room_category_default
    end

    def standard_rate_plan
      @standard_rate_plan ||= @room_type.standard_rate_plan
    end

    def room_type_rate_plan
      return @supplied_room_type_rate_plan if @supplied_room_type_rate_plan.present?
      return if @rate_plan.nil?

      @room_type_rate_plan ||= if @room_type.association(:room_type_rate_plans).loaded?
        @room_type.room_type_rate_plans.find { |assignment| assignment.rate_plan_id == @rate_plan.id }
      else
        @room_type.room_type_rate_plans.find_by(rate_plan_id: @rate_plan.id)
      end
    end

    def find_rate(rate_plan_id)
      rates.find do |rate|
        rate.room_type_id == @room_type.id &&
          rate.date == @date &&
          rate.currency == @currency &&
          rate.rate_plan_id == rate_plan_id
      end
    end

    def rates
      @rates ||= if @room_rates
        @room_rates.to_a
      elsif @room_type.association(:room_rates).loaded?
        @room_type.room_rates.target
      else
        @room_type.room_rates.where(date: @date, currency: @currency).to_a
      end
    end

    def default_currency
      @rate_plan&.currency.presence || @room_type.hotel.default_currency.presence || "MYR"
    end
  end
end
