# frozen_string_literal: true

module Folios
  module Lifecycle
    class IssueClosingDocument
      DIRECT_BILL_SETTLEMENT = "direct_bill"
      Outcome = Data.define(:folio_invoice, :ar_invoice)

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
          raise ArgumentError, "Direct Bill folios cannot also have a folio invoice." if @folio.folio_invoice.present? || @folio.invoice_number.present?

          ar_invoice = Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio: @folio, balance: @balance)
          return Outcome.new(folio_invoice: nil, ar_invoice:)
        end

        folio_invoice = FolioInvoices::Finalize.call!(folio: @folio, issued_by: @user, balance: @balance)
        Outcome.new(folio_invoice:, ar_invoice: nil)
      end
    end
  end
end
