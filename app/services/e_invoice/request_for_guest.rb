# frozen_string_literal: true

module EInvoice
  # The rules that decide whether a guest can ask for an e-invoice.
  #
  # These lived in Guest::BookingsController. The stay page asks the same
  # question, so the rules moved here and both callers read one answer.
  class RequestForGuest
    Result = ApplicationResult.define(:already_queued)

    def initialize(booking:)
      @booking = booking
    end

    def call
      return failure("This booking's payment has not concluded yet.") unless booking.payment_concluded?

      unless booking.e_invoice_requestable?
        return failure("E-invoice requests are only available within the same calendar month as the payment.")
      end

      return failure("An e-invoice has already been issued for this booking.") if booking.e_invoice_already_issued?
      return failure(missing_details_message) if missing_details.any?

      if booking.pending_guest_e_invoice_submission
        return Result.failure(
          "Your e-invoice is already being prepared. You will receive it shortly.",
          already_queued: true
        )
      end

      EInvoice::AutoIssueJob.perform_later(booking.id, requested_by_guest: true)
      Result.success(already_queued: false)
    end

    private

    attr_reader :booking

    # Say what is missing while the guest can still supply it, rather than
    # accepting the request and failing LHDN validation days later.
    def missing_details
      @missing_details ||= booking.e_invoice_buyer_details_missing
    end

    def missing_details_message
      "We need your #{missing_details.to_sentence} before we can request the e-invoice. " \
        "Please contact the hotel to update your details."
    end

    def failure(message)
      Result.failure(message, already_queued: false)
    end
  end
end
