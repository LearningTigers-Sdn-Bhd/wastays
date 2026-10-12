# frozen_string_literal: true

module ArInvoices
  class CompleteCorrection
    def self.call!(folio:, user:, send_documents: false)
      new(folio: folio, user: user, send_documents: send_documents).call!
    end

    def initialize(folio:, user:, send_documents:)
      @folio = folio
      @user = user
      @send_documents = ActiveModel::Type::Boolean.new.cast(send_documents)
    end

    # Caller holds the folio lock and transaction. No provider calls occur here.
    def call!
      correction = @folio.ar_invoice_corrections.editing.lock.first!
      original = correction.original_receivable
      original.lock!
      snapshot = Invoices::Snapshot.call(folio: @folio).deep_stringify_keys
      balance = @folio.outstanding_balance.to_d
      raise ArgumentError, "A corrected AR folio cannot have a negative balance." if balance.negative?
      if unchanged?(correction, snapshot, balance)
        original.invoice.update!(state: "finalized")
        correction.update!(status: "unchanged", closed_by: @user, completed_at: Time.current)
        return original
      end

      allocations = original.ar_payment_allocations.active.includes(:ar_payment).to_a
        .sort_by { |allocation| [ allocation.ar_payment.received_at, allocation.ar_payment_id, allocation.id ] }
      allocations.map(&:ar_payment).uniq(&:id).sort_by(&:id).each(&:lock!)
      allocations.each do |allocation|
        result = ArPayments::ReverseAllocation.call(allocation: allocation, user: @user,
          reason: correction.reason, correction: correction)
        raise ArgumentError, result.error unless result.success?
      end
      original.update!(status: "void", outstanding_amount: 0,
        metadata: original.metadata.merge("correction_id" => correction.id))
      original.invoice.update!(state: "voided")
      @folio.association(:invoice).reset
      @folio.association(:ar_invoice).reset
      @folio.association(:receivable).reset

      replacement = if balance.positive?
        Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio: @folio, balance: balance, due_on: original.due_on)
      end
      carry_payments!(allocations, replacement) if replacement
      correction.update!(
        replacement_receivable: replacement, corrected_snapshot: snapshot,
        credit_reference: "#{original.formatted_invoice_number}-CN", closed_by: @user,
        send_documents: @send_documents, status: "processing", completed_at: Time.current,
        metadata: correction.metadata.merge(
          "carried_payment_amount" => (replacement&.paid_amount).to_d.to_s("F"),
          "unapplied_payment_amount" => (allocations.sum { |row| row.amount.to_d } - (replacement&.paid_amount).to_d).to_s("F")
        )
      )
      FinancialControls::AuditEventRecorder.call!(
        hotel: @folio.hotel, business_date: @folio.hotel.current_business_date,
        event_type: "ar_invoice_corrected", source: "folio_window", actor: @user,
        booking_folio: @folio, booking: @folio.booking, reason: correction.reason,
        amount: balance, currency: @folio.currency,
        metadata: { correction_id: correction.id, original_receivable_id: original.id,
                    replacement_receivable_id: replacement&.id, credit_reference: correction.credit_reference }
      )
      replacement
    end

    private

    def unchanged?(correction, snapshot, balance)
      original = correction.original_snapshot
      original["transactions"] == snapshot["transactions"] &&
        original.dig("folio", "label") == snapshot.dig("folio", "label") &&
        correction.original_receivable.amount.to_d == balance
    end

    def carry_payments!(allocations, replacement)
      allocations.each do |allocation|
        break unless replacement.reload.outstanding_amount.positive?

        amount = [ allocation.amount.to_d, replacement.outstanding_amount.to_d ].min
        result = ArPayments::AllocatePayment.call(payment: allocation.ar_payment, user: @user,
          allocations: { replacement.id => amount })
        raise ArgumentError, result.error unless result.success?
      end
    end
  end
end
