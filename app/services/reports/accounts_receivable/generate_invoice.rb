# frozen_string_literal: true

module Reports
  module AccountsReceivable
    # Compatibility entry point. Both settled and direct-bill documents now use
    # the same immutable snapshot-backed invoice renderer.
    class GenerateInvoice
      def initialize(invoice:, printed_by: nil)
        @receivable = invoice
        @printed_by = printed_by
      end

      def generate
        Reports::Bookings::GenerateInvoice.new(
          invoice: @receivable.invoice,
          receivable: @receivable,
          printed_by: @printed_by
        ).generate
      end
    end
  end
end
