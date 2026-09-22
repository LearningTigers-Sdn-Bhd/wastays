# frozen_string_literal: true

module ArPaymentSubmissions
  # A hotel accepting an agent's remittance slip.
  #
  # The state change itself stays on ArPaymentSubmission, which is the record
  # that owns it. What this adds is the consequence: telling the agent, and --
  # for a booking prepayment -- posting the money where the desk will actually
  # look for it. That belongs in a service rather than a model callback: a
  # folio posting is a side effect with its own failure modes, and a submission
  # approved in a console or a fixture should not need a folio to exist.
  #
  # Notifying never fails the approval; the folio posting does. An agent's
  # remittance approved but never posted would leave the desk reading the stay
  # as unpaid at checkout despite the hotel having told the agent otherwise --
  # a worse outcome than refusing the approval and asking someone to look.
  class Approve
    class PostingFailed < StandardError; end

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
      ActiveRecord::Base.transaction do
        @submission.approve!(ar_payment: @ar_payment, reviewed_by: @reviewed_by)
        post_to_folio!
      end
      notify
      Result.new(submission: @submission)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(submission: @submission, error: e.record.errors.full_messages.to_sentence)
    rescue PostingFailed => e
      Result.new(submission: @submission, error: e.message)
    end

    private

    # Only a booking prepayment has a folio waiting on it -- an invoice
    # settlement is ordinary AR and is posted through the invoice, not a
    # booking. `ar_payment_submission.approve!` already cleared the payment
    # deadline; this is what makes the booking actually read as paid.
    def post_to_folio!
      booking = @submission.booking
      return if booking.blank?

      folio = booking.booking_folio
      raise PostingFailed, "This booking has no folio to record the payment against." if folio.blank?

      result = ::Folios::Transactions::InsertTransaction.new(
        booking_folio: folio,
        amount: @submission.amount,
        transaction_type: "payment",
        category: "booking_payment",
        user: @reviewed_by,
        description: "Agent prepayment via remittance slip ##{@submission.reference_number}",
        options: folio_posting_options(folio)
      ).call
      raise PostingFailed, result.error unless result.success?

      ::Deposits::SyncBookingPaymentStatus.call(booking)
    end

    # A slip is usually approved well before checkout, but a review can lag
    # behind it -- the folio has already closed by the time the hotel gets to
    # the slip. The override is only reached for that case; the ordinary path
    # posts to an open folio like any other payment.
    def folio_posting_options(folio)
      options = {
        system_posting: true,
        posting_source: "ar_payment_submission_approval",
        metadata: {
          ar_payment_submission_id: @submission.id,
          ar_payment_id: @ar_payment.id
        }
      }
      return options unless folio.status == "closed"

      options.merge(
        override_closed_folio: true,
        correction_reason: "ar_payment_submission_approved_after_checkout",
        correction_note: "Agent remittance slip ##{@submission.reference_number} approved after the folio closed."
      )
    end

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
