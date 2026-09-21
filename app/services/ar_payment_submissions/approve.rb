# frozen_string_literal: true

module ArPaymentSubmissions
  # A hotel accepting an agent's remittance slip.
  #
  # The state change itself stays on ArPaymentSubmission, which is the record
  # that owns it. What this adds is the consequence: telling the agent. That
  # belongs in a service rather than a model callback, because a notification is
  # an external side effect and a submission approved in a console or a fixture
  # should not send mail.
  #
  # Notifying never fails the approval. The money is recorded either way, and a
  # mail server being down is not a reason to leave a slip unreviewed.
  class Approve
    Result = Struct.new(:submission, :error, keyword_init: true) do
      def success? = error.blank?
    end

    def self.call(...) = new(...).call

    def initialize(submission:, ar_payment:, reviewed_by:)
      @submission = submission
      @ar_payment = ar_payment
      @reviewed_by = reviewed_by
    end

    def call
      @submission.approve!(ar_payment: @ar_payment, reviewed_by: @reviewed_by)
      notify
      Result.new(submission: @submission)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(submission: @submission, error: e.record.errors.full_messages.to_sentence)
    end

    private

    # Only a booking prepayment has an agent waiting on an answer about rooms.
    # An invoice settlement is ordinary AR and is not chased this way.
    def notify
      booking = @submission.booking
      return if booking.blank?

      Notifications::QueueAgentPaymentNotice.call(
        booking: booking,
        notification_type: "agent_payment_approved",
        trigger_event: "ar_payment_submission_approved",
        idempotency_key: "agent_payment_approved:#{@submission.id}",
        extra: {
          submission_id: @submission.id,
          reference_number: @submission.reference_number,
          reviewed_at: @submission.reviewed_at&.iso8601
        }
      )
    rescue StandardError => e
      Rails.logger.error("Failed to notify agent of approved submission #{@submission.id}: #{e.message}")
    end
  end
end
