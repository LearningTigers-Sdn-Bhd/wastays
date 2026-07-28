# frozen_string_literal: true

module FolioInvoices
  class Finalize
    def self.call!(folio:, issued_by:, balance:)
      new(folio:, issued_by:, balance:).call!
    end

    def initialize(folio:, issued_by:, balance:)
      @folio = folio
      @issued_by = issued_by
      @balance = balance.to_d
    end

    def call!
      @folio.with_lock do
        @folio.reload
        validate!

        invoice = @folio.folio_invoice
        return invoice if invoice&.finalized?

        invoice ||= create_invoice!
        finalize_revision!(invoice) if invoice.under_correction?
        invoice
      end
    end

    private

    def validate!
      raise ArgumentError, "Folio must be closed before its invoice is finalized." unless @folio.closed?
      raise ArgumentError, "Settled folio invoice requires a zero balance." unless @balance.zero?
      raise ArgumentError, "Direct Bill folios use the AR invoice as their payable document." if @folio.ar_invoice.present?
    end

    def create_invoice!
      ensure_identifier!
      issued_at = Time.current
      invoice = FolioInvoice.create!(
        hotel: @folio.hotel,
        booking_folio: @folio,
        issued_by: @issued_by,
        invoice_number: @folio.invoice_number,
        invoice_year: @folio.invoice_year,
        invoice_reference: @folio.invoice_reference,
        state: "finalized",
        current_revision_number: 1,
        issued_at:
      )
      create_revision!(invoice, revision_number: 1, issued_at:)
      invoice
    end

    def finalize_revision!(invoice)
      revision_number = invoice.current_revision_number + 1
      issued_at = Time.current
      create_revision!(invoice, revision_number:, issued_at:)
      invoice.update!(state: "finalized", current_revision_number: revision_number)
    end

    def create_revision!(invoice, revision_number:, issued_at:)
      invoice.revisions.create!(
        hotel: invoice.hotel,
        issued_by: @issued_by,
        revision_number:,
        document_reference: document_reference(invoice, revision_number),
        snapshot: FolioInvoices::Snapshot.call(folio: @folio),
        issued_at:
      )
    end

    def ensure_identifier!
      return if @folio.invoice_number.present?

      allocation = DocumentIdentifiers::Issuer.issue!(hotel: @folio.hotel, type: :invoice)
      @folio.assign_invoice_identifier_for_closure!(allocation)
    end

    def document_reference(invoice, revision_number)
      return invoice.invoice_reference if revision_number == 1

      "#{invoice.invoice_reference}-#{revision_number}"
    end
  end
end
