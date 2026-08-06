# frozen_string_literal: true

module Bookings
  class RateSelection
    Selection = Data.define(:rate_plan, :tier, :token)

    TIER_PATTERN = /\Atier_(walk_in|corporate)_(\d+)\z/

    def self.resolve(room_type:, value:)
      new(room_type:, value:).resolve
    end

    def self.current(booking_room)
      rate_plan = booking_room&.rate_plan
      tier = booking_room&.nightly_rate_snapshot.to_h.values.filter_map do |entry|
        entry.to_h["rate_tier"].presence
      end.first&.to_sym || :standard
      token = tier == :standard ? rate_plan&.id&.to_s : tier_token(tier, rate_plan&.id)

      Selection.new(rate_plan:, tier:, token: token.to_s)
    end

    def self.tier_token(tier, rate_plan_id)
      "tier_#{tier}_#{rate_plan_id}"
    end

    def initialize(room_type:, value:)
      @room_type = room_type
      @value = value.to_s
    end

    def resolve
      return Selection.new(rate_plan: nil, tier: :standard, token: "") if value.blank?

      if (match = TIER_PATTERN.match(value))
        tier = match[1].to_sym
        rate_plan = standard_plans.find { |plan| plan.id == match[2].to_i } || standard_plans.first
        raise ActiveRecord::RecordNotFound, "Selected rate is not available for this room category." unless rate_plan

        return Selection.new(
          rate_plan:,
          tier:,
          token: self.class.tier_token(tier, rate_plan.id)
        )
      end

      rate_plan = room_type.rate_plans.find_by(id: value)
      return Selection.new(rate_plan: nil, tier: :standard, token: "") unless rate_plan

      Selection.new(rate_plan:, tier: :standard, token: rate_plan.id.to_s)
    end

    private

    attr_reader :room_type, :value

    def standard_plans
      @standard_plans ||= room_type.rate_plans.order(:name, :id).reject(&:special_tier?)
    end
  end
end
