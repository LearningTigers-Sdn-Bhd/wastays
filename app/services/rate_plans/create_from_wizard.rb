# frozen_string_literal: true

module RatePlans
  # Turns a completed wizard draft into a rate plan, its category assignments,
  # and — for a per-person property — a complete occupancy matrix per category.
  #
  # Derived and Auto are materialised here rather than stored as rules: there is
  # no schema for a per-occupancy rule, and a matrix written once is a matrix
  # that can be checked for completeness. The consequence is that a per-person
  # plan does not track later changes to the category's standard rate; ongoing
  # changes belong to Rates & Availability.
  class CreateFromWizard
    Result = Data.define(:rate_plan, :error)

    def self.call(...) = new(...).call

    def initialize(wizard:)
      @wizard = wizard
    end

    def call
      return Result.new(rate_plan: nil, error: "This draft is not complete yet.") unless @wizard.ready?

      rate_plan = nil
      # RoomTypeRatePlan#trigger_ari_sync fires per assignment, which would
      # enqueue a separate 500-day push for every category on the plan. One
      # batched push after the transaction replaces them.
      with_batched_ari_sync do
        ActiveRecord::Base.transaction do
          rate_plan = build_rate_plan
          rate_plan.save!
          @wizard.selected_room_types.each { |room_type| assign!(rate_plan, room_type) }
        end
      end

      push_ari(rate_plan)
      Result.new(rate_plan: rate_plan, error: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(rate_plan: nil, error: e.record.errors.full_messages.to_sentence)
    end

    private

    def build_rate_plan
      plan = @wizard.hotel.rate_plans.build(@wizard.rate_plan_attributes)
      plan.kind = "custom"
      plan
    end

    def assign!(rate_plan, room_type)
      pricing = @wizard.room_pricing(room_type)
      assignment = rate_plan.room_type_rate_plans.create!(
        room_type: room_type,
        **pricing.assignment_attributes
      )

      pricing.occupancy_matrix.each do |adults, price|
        assignment.occupancy_prices.create!(adults: adults, price: price)
      end
    end

    def with_batched_ari_sync
      Thread.current[:skip_ari_sync] = true
      yield
    ensure
      Thread.current[:skip_ari_sync] = nil
    end

    def push_ari(rate_plan)
      return if rate_plan.blank?

      ChannelManagers::SyncRatePlanAri.call(
        rate_plan: rate_plan,
        room_type_ids: @wizard.selected_room_types.map(&:id)
      )
    end
  end
end
