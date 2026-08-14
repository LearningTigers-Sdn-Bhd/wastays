# frozen_string_literal: true

module Onboarding
  class TransitionLifecycle
    Result = ApplicationResult.define(:hotel)
    TRANSITIONS = {
      "setup" => %w[pending_review],
      "pending_review" => %w[setup ready_to_launch],
      "ready_to_launch" => %w[live],
      "live" => %w[suspended],
      "suspended" => %w[live]
    }.freeze
    EVENTS = {
      [ "setup", "pending_review" ] => "submitted",
      [ "pending_review", "setup" ] => "changes_requested",
      [ "pending_review", "ready_to_launch" ] => "approved",
      [ "ready_to_launch", "live" ] => "launched",
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
      result = nil
      @hotel.with_lock do
        from = @hotel.reload.status
        unless TRANSITIONS.fetch(from, []).include?(@to)
          result = Result.failure("Hotel cannot transition from #{from} to #{@to}.", hotel: @hotel)
          next
        end
        if from == "ready_to_launch" && @to == "live" && !launch_decision_recorded?
          result = Result.failure("Hotel cannot launch until the owner completes the launch decision.", hotel: @hotel)
          next
        end
        if readiness_required?(from) && !Readiness.new(hotel: @hotel).call.ready
          destination = @to == "ready_to_launch" ? "approval" : (@to == "live" ? "launch" : "submission")
          result = Result.failure("Hotel onboarding is not ready for #{destination}.", hotel: @hotel)
          next
        end

        @hotel.update!(status: @to)
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: EVENTS.fetch([ from, @to ]),
          metadata: @metadata,
          occurred_at: Time.current
        )
        result = Result.success(hotel: @hotel)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, hotel: @hotel)
    end

    private

    def readiness_required?(from)
      (from == "setup" && @to == "pending_review") ||
        (from == "pending_review" && @to == "ready_to_launch") ||
        (from == "ready_to_launch" && @to == "live")
    end

    def launch_decision_recorded?
      @hotel.training_data_decision.in?(%w[keep reset]) &&
        @hotel.training_completed_at.present? &&
        @hotel.training_completed_by_id.present? &&
        @hotel.onboarding_submissions.where(status: "approved").exists?
    end
  end
end
