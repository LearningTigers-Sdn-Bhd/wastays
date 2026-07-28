# frozen_string_literal: true

module FolioInvoicePackages
  class Preview
    Result = Data.define(:groups) do
      def valid_groups
        groups.select { |group| group.recipient.email.present? }
      end

      def skipped_groups
        groups.reject { |group| group.recipient.email.present? }
      end

      def invoice_count
        groups.sum { |group| group.invoices.size }
      end

      def resendable?
        valid_groups.any?
      end

      def tooltip
        return "No finalized invoices are available to resend." if groups.empty?
        return "Cannot resend—this payer has no saved email." if valid_groups.empty?

        if groups.one?
          group = groups.first
          count = group.invoices.size
          "Resend #{count} finalized #{count == 1 ? 'invoice' : 'invoices'} to #{group.recipient.email}."
        else
          "Send separate invoice emails to #{valid_groups.size} saved payer contacts."
        end
      end
    end

    def self.call(hotel:, bookings:)
      invoices = Collect.call(hotel:, bookings:)
      Result.new(groups: GroupByPayer.call(invoices:))
    end
  end
end
