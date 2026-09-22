# frozen_string_literal: true

module ArPaymentSubmissions
  # A hotel turning down an agent's remittance slip.
  #
  # A rejection restarts the release clock, so this is the notification that
  # matters most in the whole payment path: an agent who is not told will find
  # out when the rooms are gone. The mail therefore has to carry both halves --
  # **why** it was rejected, and the **new** deadline.
  #
  # `reject!` has already extended `payment_due_at` by the time the review took
  # (ArPaymentSubmission#restart_payment_clock), so the booking is reloaded
  # before the payload is built. Quoting the old deadline would be worse than
  # quoting none.
  class Reject
    Result = Struct.new(:submission, :error, keyword_init: true) do
      def success? = error.blank?
    end

    def self.call(...) = new(...).call

    def initialize(submission:, reason:, reviewed_by:)
      @submission = submission
      @reason = reason
      @reviewed_by = reviewed_by
    end

    def call
      unless @submission.reject!(reason: @reason, reviewed_by: @reviewed_by)
        return Result.new(submission: @submission, error: @submission.errors.full_messages.to_sentence)
      end

      notify
      Result.new(submission: @submission)
    end

    private

    def notify
      booking = @submission.booking
      return if booking.blank?

      booking.reload
      Notifications::QueueAgentPaymentNotice.call(
        booking: booking,
        notification_type: "agent_payment_rejected",
        trigger_event: "ar_payment_submission_rejected",
        idempotency_key: "agent_payment_rejected:#{@submission.id}",
        extra: {
          submission_id: @submission.id,
          reference_number: @submission.reference_number,
          rejection_reason: @submission.rejection_reason,
          reviewed_at: @submission.reviewed_at&.iso8601
        }
      )
    rescue StandardError => e
      Rails.logger.error("Failed to notify agent of rejected submission #{@submission.id}: #{e.message}")
    end
  end
end
