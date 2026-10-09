# frozen_string_literal: true

module EInvoice
  class ResolveArOriginal
    def self.call!(invoice:)
      submissions = invoice.booking.e_invoice_submissions.where(hotel: invoice.hotel).where(document_type: "01").where.not(status: "cancelled")
      linked = submissions.where(invoice: invoice).to_a
      candidates = linked.presence || submissions.where(invoice_id: nil, internal_id: invoice.invoice_reference).to_a
      if candidates.empty?
        # Booking-level documents cannot safely be assigned to one of several payers.
        if submissions.where(invoice_id: nil).exists?
          raise ArgumentError, "The booking e-invoice is not linked to this AR invoice. Link the original document before reopening."
        end
        return nil
      end
      raise ArgumentError, "More than one e-invoice matches this AR invoice." unless candidates.one?
      submission = candidates.first
      raise ArgumentError, "Wait for the original e-invoice to validate before reopening." if submission.status.in?(%w[pending submitted])
      return nil if submission.invalid?
      raise ArgumentError, "The original e-invoice has no validated UUID or buyer snapshot." if submission.uuid.blank? || submission.buyer_snapshot.blank?
      payer = invoice.current_revision.snapshot.dig("payer", "name")
      unless submission.buyer_snapshot["name"].to_s.casecmp?(payer.to_s)
        raise ArgumentError, "The original e-invoice buyer does not match this company folio."
      end
      submission.update!(invoice: invoice) if submission.invoice_id.nil?
      submission
    end
  end
end
