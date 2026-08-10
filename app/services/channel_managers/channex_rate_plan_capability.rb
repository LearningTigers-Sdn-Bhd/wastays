# frozen_string_literal: true

module ChannelManagers
  # Decides whether one Wastays rate plan can be represented by Channex.
  # Per-person support is assignment-specific because every room category has
  # its own capacity and therefore its own required occupancy ladder.
  class ChannexRatePlanCapability
    Result = Data.define(:status, :reason, :missing_occupancies) do
      def supported? = status.in?(%i[full flattened])
      def flattened? = status == :flattened
      def unsupported? = status == :unsupported
    end

    def self.call(...) = new(...).call

    def initialize(rate_plan:, room_type: nil)
      @rate_plan = rate_plan
      @room_type = room_type
    end

    def call
      return unsupported("#{rate_plan.kind.humanize} plans are not distributed to channels") unless distributable_kind?

      assignments = assignments_in_scope
      return unsupported("Attach the plan to at least one room category") if assignments.empty?
      return supported(:full) if rate_plan.sell_mode == "per_room"

      missing = assignments.each_with_object({}) do |assignment, result|
        required = (1..[ assignment.room_type.max_adults.to_i, 1 ].max).to_a
        present = available_occupancies(assignment)
        result[assignment.room_type_id] = required - present if (required - present).any?
      end
      return unsupported("Complete the adult occupancy prices", missing) if missing.any?

      if rate_plan.age_banded?
        return unsupported("Set both flat Channex child and infant fees") unless flat_child_fees_configured?

        return supported(:flattened)
      end

      supported(:full)
    end

    private

    attr_reader :rate_plan, :room_type

    def distributable_kind?
      rate_plan.kind.in?(RatePlan::DISTRIBUTABLE_KINDS)
    end

    # Callers that already preloaded the assignments (the channels dashboard,
    # the ARI push) get to keep that work; a fresh relation would discard it.
    def assignments_in_scope
      scope = if rate_plan.association(:room_type_rate_plans).loaded?
        rate_plan.room_type_rate_plans.to_a
      else
        rate_plan.room_type_rate_plans.includes(:room_type, :occupancy_prices).to_a
      end
      room_type ? scope.select { |assignment| assignment.room_type_id == room_type.id } : scope
    end

    def flat_child_fees_configured?
      !rate_plan.channex_children_fee.nil? && !rate_plan.channex_infant_fee.nil?
    end

    def available_occupancies(assignment)
      occupancies = assignment.occupancy_prices.map(&:adults)
      return occupancies unless assignment.derives_price?

      standard_assignment = standard_assignment_for(assignment.room_type)
      standard_occupancies = standard_assignment ? standard_assignment.occupancy_prices.map(&:adults) : []
      occupancies | standard_occupancies
    end

    def standard_assignment_for(room_type)
      if room_type.association(:room_type_rate_plans).loaded?
        room_type.room_type_rate_plans.find { |assignment| assignment.rate_plan.kind == "standard" }
      else
        room_type.room_type_rate_plans
          .joins(:rate_plan)
          .includes(:occupancy_prices)
          .find_by(rate_plans: { kind: "standard" })
      end
    end

    def supported(status)
      Result.new(status: status, reason: nil, missing_occupancies: {})
    end

    def unsupported(reason, missing = {})
      Result.new(status: :unsupported, reason: reason, missing_occupancies: missing)
    end
  end
end
