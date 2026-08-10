# frozen_string_literal: true

module Bookings
  # Computes a single night's price for a given adults/children party from an
  # already-loaded RoomRate (or nil) and RatePlan. Extracted so the real
  # pricing engine (CalculateStayPrice) and pricing previews (e.g. the AI
  # concierge's search tool) share one formula and can never diverge -
  # callers that already have the RoomRate loaded should pass it in directly
  # rather than letting this class query the database.
  class NightlyPaxPrice
    # The parts that make up a per-person night. Quotes freeze these so a
    # breakdown shown months later still reconciles to the price charged,
    # instead of being re-derived from since-edited rate plans.
    # adults_cost/children_cost are nil for per-room plans, which have no split.
    Breakdown = Data.define(:total, :adults_cost, :children_cost, :supplement)

    def self.call(...)
      new(...).call
    end

    def self.breakdown(...)
      new(...).breakdown
    end

    def initialize(base_nightly_rate:, rate:, rate_plan:, adults:, children:, child_ages: [], adult_occupancy_price: nil)
      @base_nightly_rate = base_nightly_rate
      @rate = rate
      @rate_plan = rate_plan
      @adults = adults.to_i
      @children = children.to_i
      ages = Array(child_ages).map(&:to_i)
      @child_ages = (ages.size == @children) ? ages : []
      @adult_occupancy_price = adult_occupancy_price
    end

    def call
      breakdown.total
    end

    def breakdown
      if @rate_plan&.sell_mode == "per_person"
        per_person_breakdown
      else
        Breakdown.new(total: per_room_price, adults_cost: nil, children_cost: nil, supplement: 0.to_d)
      end
    end

    private

    def per_person_breakdown
      adults_cost = @adult_occupancy_price || (@adults * @base_nightly_rate)
      children_cost =
        if @child_ages.any?
          @child_ages.sum { |age| per_child_price(age) }
        else
          @children * @base_nightly_rate * (@rate_plan.child_price_multiplier || 1.to_d)
        end

      # An occupancy matrix already prices a lone adult, so the supplement
      # applies only when we fell back to the per-person rate.
      supplement =
        if @adult_occupancy_price.nil? && (@adults + @children) == 1
          @rate&.single_supplement || @rate_plan.single_supplement || 0.to_d
        else
          0.to_d
        end

      Breakdown.new(
        total: adults_cost + children_cost + supplement,
        adults_cost: adults_cost,
        children_cost: children_cost,
        supplement: supplement
      )
    end

    def per_room_price
      price = @base_nightly_rate

      base_occ = @rate&.base_occupancy || @rate_plan&.base_occupancy || 2
      extra_charge = @rate&.extra_pax_charge || @rate_plan&.extra_pax_charge || 0.to_d

      billable_pax = @adults + @children
      if billable_pax > base_occ && extra_charge.positive?
        price += (billable_pax - base_occ) * extra_charge
      end

      price
    end

    def per_child_price(age)
      band = @rate_plan.age_banded? ? @rate_plan.band_for_age(age) : nil
      return band.price_for(@base_nightly_rate) if band

      @base_nightly_rate * (@rate_plan.child_price_multiplier || 1.to_d)
    end
  end
end
