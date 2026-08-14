# frozen_string_literal: true

module Onboarding
  class RequestTrainingReset
    Result = ApplicationResult.define(:hotel, :already_queued)

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:)
      @hotel = hotel
      @actor = actor
    end

    def call
      enqueue = false
      already_queued = false
      error = nil

      Hotel.transaction do
        @hotel.lock!
        @hotel.reload

        if @hotel.status == "live" && @hotel.training_data_decision == "reset"
          already_queued = true
          next
        end

        unless @hotel.status == "ready_to_launch" && @hotel.training_data_decision.nil?
          error = "This property is not awaiting its training-data decision."
          raise ActiveRecord::Rollback
        end

        if @hotel.training_reset_state.in?(%w[queued processing])
          already_queued = true
          next
        end

        retrying = @hotel.training_reset_state == "failed"
        @hotel.update!(training_reset_state: "queued")
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: retrying ? "training_reset_retried" : "training_reset_requested",
          metadata: { source: "hotel_portal" },
          occurred_at: Time.current
        )
        enqueue = true
      end

      return Result.failure(error, hotel: @hotel, already_queued:) if error

      if enqueue
        job = ResetTrainingDataJob.perform_later(@hotel.id, @actor.id)
        raise "The training reset could not be queued." unless job
      end
      Result.success(hotel: @hotel, already_queued:)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, hotel: @hotel, already_queued: false)
    rescue StandardError => e
      mark_enqueue_failed(e)
      Rails.error.report(e, handled: true, severity: :error, context: { hotel_id: @hotel.id, operation: "training_reset_enqueue" })
      Result.failure(e.message, hotel: @hotel, already_queued: false)
    end

    private

    def mark_enqueue_failed(error)
      Hotel.transaction do
        @hotel.lock!
        @hotel.reload
        next unless @hotel.status == "ready_to_launch" && @hotel.training_reset_state == "queued"

        @hotel.update!(training_reset_state: "failed")
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: "training_reset_failed",
          metadata: { error_class: error.class.name, error_message: error.message.to_s.truncate(500), phase: "enqueue" },
          occurred_at: Time.current
        )
      end
    end
  end
end
