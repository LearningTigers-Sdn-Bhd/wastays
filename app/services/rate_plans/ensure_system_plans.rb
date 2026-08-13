# frozen_string_literal: true

module RatePlans
  # Ensures that a room category owns one dedicated plan for each system rate.
  # Existing shared plans are deliberately left attached for historical use;
  # they never satisfy this invariant for a newly initialized category.
  class EnsureSystemPlans
    SYSTEM_PLANS = {
      "standard" => "Standard Rate",
      "walk_in" => "Walk-in Rate",
      "corporate" => "Corporate Rate"
    }.freeze

    def self.call!(...) = new(...).call!

    def initialize(room_type:)
      @room_type = room_type
    end

    def call!
      room_type.with_lock do
        standard = ensure_plan!("standard")
        ensure_plan!("walk_in", anchor: standard)
        ensure_plan!("corporate", anchor: standard)
      end

      room_type.reset_rate_plan_cache!
    end

    private

    attr_reader :room_type

    def ensure_plan!(kind, anchor: nil)
      existing = dedicated_plan(kind)
      return existing if existing

      plan = room_type.hotel.rate_plans.create!(plan_attributes(kind, anchor))
      copy_age_bands!(anchor, plan) if anchor

      if kind == "standard"
        plan.room_type_rate_plans.create!(room_type: room_type)
        # BootstrapAssignment resolves the anchor to copy its occupancy ladder,
        # so the category has to see the plan just created before the tiers run.
        room_type.reset_rate_plan_cache!
      else
        BootstrapAssignment.call!(rate_plan: plan, room_type: room_type)
      end

      plan
    end

    def dedicated_plan(kind)
      room_type.rate_plans
        .where(kind: kind)
        .where(id: RoomTypeRatePlan.group(:rate_plan_id).having("COUNT(*) = 1").select(:rate_plan_id))
        .order(:id)
        .first
    end

    def plan_attributes(kind, anchor)
      source = anchor || room_type.standard_rate_plan
      {
        name: SYSTEM_PLANS.fetch(kind),
        kind: kind,
        currency: source&.currency || room_type.hotel.default_currency || "MYR",
        base_occupancy: source&.base_occupancy || 2,
        single_supplement: source&.single_supplement || 0,
        child_price_multiplier: source&.child_price_multiplier || 1,
        extra_pax_charge: source&.extra_pax_charge || 0
      }
    end

    def copy_age_bands!(source, target)
      source.rate_plan_age_bands.find_each do |band|
        target.rate_plan_age_bands.create!(band.attributes.slice(
          "min_age", "max_age", "pricing_mode", "price_value", "label", "position"
        ))
      end
    end
  end
end
