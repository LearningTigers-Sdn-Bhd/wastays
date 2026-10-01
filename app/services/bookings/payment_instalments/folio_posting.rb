# frozen_string_literal: true

module Bookings
  module PaymentInstalments
    # Posting an agent stage's money to the booking's folio, the way approving a
    # slip does: a system posting, because who may do it is decided by the
    # controller's permission check, with an override when the folio has already
    # closed (a payment or refund can be recorded after checkout).
    module FolioPosting
      class PostingFailed < StandardError; end

      private

      # `signed_amount` is positive for a payment and negative for a refund.
      def post_to_folio!(booking:, signed_amount:, category:, description:, user:, metadata:)
        folio = booking.booking_folio
        raise PostingFailed, "This booking has no folio to record the money against." if folio.blank?

        result = ::Folios::Transactions::InsertTransaction.new(
          booking_folio: folio, amount: signed_amount, transaction_type: "payment", category: category,
          user: user, description: description, options: posting_options(folio, metadata)
        ).call
        raise PostingFailed, result.error unless result.success?

        result.transaction
      end

      def posting_options(folio, metadata)
        options = { system_posting: true, posting_source: "agent_payment_panel", metadata: metadata }
        return options unless folio.status == "closed"

        options.merge(
          override_closed_folio: true,
          correction_reason: "agent_payment_recorded_after_checkout",
          correction_note: "Recorded from the agent payments panel after the folio closed."
        )
      end
    end
  end
end
