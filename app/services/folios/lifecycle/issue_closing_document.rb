# frozen_string_literal: true

module Folios
  module Lifecycle
    class IssueClosingDocument
      DIRECT_BILL_SETTLEMENT = "direct_bill"
      Outcome = Data.define(:invoice, :receivable) do
        def folio_invoice
          invoice if invoice&.kind_settled?
        end

        def ar_invoice
          receivable
        end
      end

      def self.call!(folio:, settlement_method:, balance:, user:)
        new(folio:, settlement_method:, balance:, user:).call!
      end

      def initialize(folio:, settlement_method:, balance:, user:)
        @folio = folio
        @settlement_method = settlement_method.to_s
        @balance = balance.to_d
        @user = user
      end

      def call!
        if @settlement_method == DIRECT_BILL_SETTLEMENT
          if @folio.invoice.present? || @folio.folio_invoice.present? || @folio.invoice_number.present?
            raise ArgumentError, "Direct Bill folios cannot also have a folio invoice."
          end

          receivable = Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio: @folio, balance: @balance)
          return Outcome.new(invoice: receivable.invoice, receivable:)
        end

        invoice = FolioInvoices::Finalize.call!(folio: @folio, issued_by: @user, balance: @balance)
        Outcome.new(invoice:, receivable: nil)
      end
    end
  end
end
