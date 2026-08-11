# frozen_string_literal: true

module Bookings
  class RateSelection
    Selection = Data.define(:rate_plan, :token)

    def self.resolve(room_type:, value:)
      new(room_type:, value:).resolve
    end

    def self.current(booking_room)
      rate_plan = booking_room&.rate_plan
      Selection.new(rate_plan:, token: rate_plan&.id&.to_s.to_s)
    end

    def initialize(room_type:, value:)
      @room_type = room_type
      @value = value.to_s
    end

    def resolve
      return Selection.new(rate_plan: nil, token: "") if value.blank?

      rate_plan = room_type.rate_plans.active.find_by(id: value)
      return Selection.new(rate_plan: nil, token: "") unless rate_plan

      Selection.new(rate_plan:, token: rate_plan.id.to_s)
    end

    private

    attr_reader :room_type, :value
  end
end
