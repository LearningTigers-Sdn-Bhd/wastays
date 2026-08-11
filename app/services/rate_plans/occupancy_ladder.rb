# frozen_string_literal: true

module RatePlans
  # Builds the complete adults => price matrix a per-person plan needs, from one
  # anchor price plus a step in each direction.
  #
  # Derived and Auto differ only in where the anchor comes from — Derived adjusts
  # the room category's standard rate, Auto takes the figure typed in the wizard
  # — so both land here, and both materialise every adult count the category can
  # hold. Completeness is the point, not a nicety: once any occupancy price
  # exists for a room type, Rates::ResolveEffectiveNightlyPrice returns a nil
  # amount for the counts that are missing, which makes the room silently
  # unsellable at those party sizes.
  class OccupancyLadder
    UNITS = %w[amount percent].freeze

    def self.call(...) = new(...).call

    def initialize(anchor:, max_adults:, primary_occupancy: 2,
                   increase_by: 0, increase_unit: "amount",
                   decrease_by: 0, decrease_unit: "amount")
      @anchor = decimal(anchor)
      @max_adults = [ max_adults.to_i, 1 ].max
      @primary_occupancy = primary_occupancy.to_i.clamp(1, @max_adults)
      @increase_by = decimal(increase_by)
      @increase_unit = UNITS.include?(increase_unit.to_s) ? increase_unit.to_s : "amount"
      @decrease_by = decimal(decrease_by)
      @decrease_unit = UNITS.include?(decrease_unit.to_s) ? decrease_unit.to_s : "amount"
    end

    # => { 1 => BigDecimal, 2 => BigDecimal, ... } for every count the category
    # can seat, rounded to the cent the price columns store.
    def call
      (1..@max_adults).index_with { |adults| price_for(adults) }
    end

    private

    def price_for(adults)
      steps = adults - @primary_occupancy
      raw = if steps.positive?
        @anchor + (step_amount(@increase_by, @increase_unit) * steps)
      elsif steps.negative?
        @anchor - (step_amount(@decrease_by, @decrease_unit) * steps.abs)
      else
        @anchor
      end

      [ raw, 0.to_d ].max.round(2)
    end

    # A percentage step is taken against the anchor rather than compounded off
    # the previous rung, so "10% per extra adult" stays linear and predictable
    # — three adults is anchor + 20%, not anchor × 1.1².
    def step_amount(value, unit)
      unit == "percent" ? (@anchor * value / 100.to_d) : value
    end

    def decimal(value)
      value.to_s.presence&.to_d || 0.to_d
    end
  end
end
