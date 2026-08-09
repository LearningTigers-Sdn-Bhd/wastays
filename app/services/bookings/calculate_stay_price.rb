# frozen_string_literal: true

module Bookings
  class CalculateStayPrice
    def initialize(room_type:, check_in:, check_out:, rate_plan:, pax: nil, adults: nil, children: nil, child_ages: [])
      @room_type = room_type
      @check_in = check_in&.to_date
      @check_out = check_out&.to_date
      @rate_plan = rate_plan

      @adults = (adults || pax || 2).to_i
      @children = (children || 0).to_i
      @pax = @adults + @children
      ages = Array(child_ages).map(&:to_i)
      @child_ages = (ages.size == @children) ? ages : []
    end

    # nil means "this stay has no price", not "this stay is free". The resolver
    # returns no amount when a night is unsellable — an occupancy the plan's
    # matrix does not cover, or a date with nothing to derive from — and
    # `nil.to_d` is 0, so summing the nights directly quoted those stays at
    # zero. Callers drop the option instead.
    def call
      return 0 if @room_type.nil? || @check_in.nil? || @check_out.nil?

      nightly = (@check_in..(@check_out - 1.day)).map do |date|
        Rates::ResolveEffectiveNightlyPrice.call(
          room_type: @room_type,
          rate_plan: @rate_plan,
          date: date,
          currency: currency,
          adults: @adults,
          children: @children,
          child_ages: @child_ages
        ).amount
      end

      return nil if nightly.any?(&:nil?)

      nightly.sum(0.to_d)
    end

    private

    def currency
      @rate_plan&.currency.presence || @room_type.hotel.default_currency.presence || "MYR"
    end
  end
end
