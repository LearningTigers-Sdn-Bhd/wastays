# frozen_string_literal: true

module ArInvoices
  class StartCorrection
    def self.call!(folio:, user:, reason:)
      raise ArgumentError, "Reason is required to reopen an AR folio." if reason.blank?
      raise ArgumentError, "The previous invoice correction must finish before reopening." if folio.ar_invoice_corrections.unresolved.exists?

      receivable = folio.ar_invoice
      receivable.lock!
      invoice = receivable.invoice
      raise ArgumentError, "This legacy AR invoice must be reconciled before correction." unless invoice&.current_revision
      unless invoice.current_revision.snapshot.key?("transactions") && invoice.current_revision.snapshot.key?("totals")
        raise ArgumentError, "This legacy AR invoice needs an issue-time snapshot before correction."
      end
      raise ArgumentError, "Only finalized AR invoices can be corrected." unless invoice.finalized?

      original_submission = EInvoice::ResolveArOriginal.call!(invoice: invoice)
      correction = folio.ar_invoice_corrections.create!(
        hotel: folio.hotel, original_receivable: receivable, opened_by: user, reason: reason,
        original_snapshot: invoice.current_revision.snapshot,
        metadata: { original_submission_id: original_submission&.id,
                    original_amount: receivable.amount.to_s("F"),
                    original_paid_amount: receivable.paid_amount.to_s("F"),
                    original_outstanding_amount: receivable.outstanding_amount.to_s("F") }
      )
      invoice.update!(state: "under_correction")
      correction
    end
  end
end
