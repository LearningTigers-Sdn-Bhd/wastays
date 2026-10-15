# frozen_string_literal: true

module RatePlans
  # Makes one attached plan the one a room category leads with. Only plans the
  # public may be sold qualify -- the primary plan is what the booking site
  # quotes first, and walk-in or OTA-only plans are never offered there.
  class MakePrimary
    Result = ApplicationResult.define

    def self.call(...) = new(...).call

    def initialize(room_type:, rate_plan:)
      @room_type = room_type
      @rate_plan = rate_plan
    end

    def call
      assignment = @room_type.room_type_rate_plans.find_by(rate_plan: @rate_plan)
      return Result.failure("#{@rate_plan.name} is not attached to #{@room_type.name}.") if assignment.blank?
      return Result.failure("An archived plan cannot be primary.") if @rate_plan.archived?
      unless @rate_plan.bookable_by?(:public)
        return Result.failure("Only plans sold on the booking site can be primary.")
      end

      RoomTypeRatePlan.transaction do
        @room_type.room_type_rate_plans.where(primary_plan: true).where.not(id: assignment.id).update_all(primary_plan: false, updated_at: Time.current)
        assignment.update!(primary_plan: true)
      end
      @room_type.reset_rate_plan_cache!

      Result.success
    end
  end
end
