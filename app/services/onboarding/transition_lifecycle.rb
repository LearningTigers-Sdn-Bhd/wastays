# frozen_string_literal: true

module Onboarding
  class TransitionLifecycle
    Result = ApplicationResult.define(:hotel)
    TRANSITIONS = {
      "setup" => %w[pending_review],
      "pending_review" => %w[setup live],
      "live" => %w[suspended],
      "suspended" => %w[live]
    }.freeze
    EVENTS = {
      [ "setup", "pending_review" ] => "submitted",
      [ "pending_review", "setup" ] => "changes_requested",
      [ "pending_review", "live" ] => "approved",
      [ "live", "suspended" ] => "suspended",
      [ "suspended", "live" ] => "reactivated"
    }.freeze

    def initialize(hotel:, to:, actor: nil, metadata: {})
      @hotel = hotel
      @to = to.to_s
      @actor = actor
      @metadata = metadata.to_h
    end

    def call
      from = LifecycleCompatibility.canonical_status(@hotel.status)
      unless TRANSITIONS.fetch(from, []).include?(@to)
        return Result.failure("Hotel cannot transition from #{from} to #{@to}.", hotel: @hotel)
      end
      if from == "setup" && @to == "pending_review" && !Readiness.new(hotel: @hotel).call.ready
        return Result.failure("Hotel onboarding is not ready for submission.", hotel: @hotel)
      end

      Hotel.transaction do
        @hotel.update!(status: @to)
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: EVENTS.fetch([ from, @to ]),
          metadata: @metadata,
          occurred_at: Time.current
        )
      end

      Result.success(hotel: @hotel)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, hotel: @hotel)
    end
  end
end
