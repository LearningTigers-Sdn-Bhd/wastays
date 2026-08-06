# frozen_string_literal: true

module Invoices
  class ReconcileLegacyDocuments
    Result = Data.define(:direct_bill_mapped, :errors)

    def self.call(batch_size: 100)
      new(batch_size:).call
    end

    def initialize(batch_size:)
      @batch_size = batch_size
      @direct_bill_mapped = 0
      @errors = []
    end

    def call
      reconcile_direct_bill
      reconcile_missing_direct_bill_revisions
      verify_integrity
      Result.new(direct_bill_mapped: @direct_bill_mapped, errors: @errors)
    end

    private

    def reconcile_direct_bill
      ArInvoice.where(invoice_id: nil).find_each(batch_size: @batch_size) do |receivable|
        receivable.with_lock do
          receivable.reload
          next if receivable.invoice_id.present?

          invoice = receivable.booking_folio.invoice || create_direct_bill_invoice(receivable)
          receivable.update_column(:invoice_id, invoice.id)
          @direct_bill_mapped += 1
        end
      rescue StandardError => e
        @errors << "ArInvoice #{receivable.id}: #{e.message}"
      end
    end

    def create_direct_bill_invoice(receivable)
      snapshot = receivable.metadata.to_h["document_snapshot"].presence
      legacy = snapshot.blank?
      snapshot ||= Invoices::Snapshot.call(folio: receivable.booking_folio)
      snapshot = snapshot.to_h.merge("legacy_generated" => true) if legacy
      issued_at = receivable.created_at

      invoice = Invoice.create!(
        hotel: receivable.hotel,
        booking_folio: receivable.booking_folio,
        kind: "direct_bill",
        invoice_number: receivable.invoice_number,
        invoice_year: receivable.invoice_year,
        invoice_reference: receivable.invoice_reference,
        state: receivable.void? ? "voided" : "finalized",
        current_revision_number: 1,
        issued_on: receivable.issued_on,
        issued_at:,
        legacy:,
        metadata: receivable.metadata.to_h.except("document_snapshot")
      )
      invoice.revisions.create!(
        hotel: receivable.hotel,
        revision_number: 1,
        document_reference: invoice.invoice_reference,
        snapshot:,
        issued_at:
      )
      invoice
    end

    def reconcile_missing_direct_bill_revisions
      Invoice.kind_direct_bill.includes(
        :revisions,
        :receivable,
        booking_folio: [
          :booking_room,
          { booking: { booking_rooms: :room_type } },
          { booking_billing_party: [ :billing_terms, :hotel_corporate_account ] },
          { folio_transactions: [ :transaction_code, :user ] },
          { hotel_corporate_account: :corporate_account }
        ]
      ).find_each(batch_size: @batch_size) do |invoice|
        next if invoice.current_revision.present?

        receivable = invoice.receivable || ArInvoice.find_by(invoice_id: invoice.id)
        raise "has no receivable" if receivable.blank?

        snapshot = receivable.metadata.to_h["document_snapshot"].presence
        legacy = snapshot.blank?
        snapshot ||= Invoices::Snapshot.call(folio: invoice.booking_folio)
        snapshot = snapshot.to_h.merge("legacy_generated" => true) if legacy
        invoice.revisions.create!(
          hotel: invoice.hotel,
          revision_number: invoice.current_revision_number,
          document_reference: invoice.invoice_reference,
          snapshot:,
          issued_at: invoice.issued_at
        )
      rescue StandardError => e
        @errors << "Invoice #{invoice.id}: #{e.message}"
      end
    end

    def verify_integrity
      @errors << "Legacy AR invoices remain unmapped." if ArInvoice.where(invoice_id: nil).exists?
      @errors << "Unified invoices are missing revisions." if Invoice.left_joins(:revisions).where(invoice_revisions: { id: nil }).exists?
      @errors << "Direct-bill invoices are missing receivables." if Invoice.kind_direct_bill.left_joins(:receivable).where(ar_invoices: { id: nil }).exists?
    end
  end
end
