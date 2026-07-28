# frozen_string_literal: true

module FolioInvoicePackages
  class GroupByPayer
    Group = Data.define(:recipient, :invoices)

    def self.call(invoices:)
      Array(invoices).group_by { |invoice| RecipientResolver.call(invoice).key }.values.map do |payer_invoices|
        Group.new(
          recipient: RecipientResolver.call(payer_invoices.first),
          invoices: payer_invoices
        )
      end
    end
  end
end
