# frozen_string_literal: true

module CorporateArPayments
  class Suggestions
    def self.call(invoices:, amount:)
      remaining = amount.to_d
      suggestions = []

      invoices.sort_by { |invoice| [ invoice.due_on, invoice.invoice_number.to_s ] }.each do |invoice|
        break if remaining <= 0

        suggested = [ invoice.outstanding_amount.to_d, remaining ].min
        remaining -= suggested
        suggestions << {
          ar_invoice_id: invoice.id,
          invoice_number: invoice.invoice_number,
          invoice_label: invoice.formatted_invoice_number,
          due_on: invoice.due_on.iso8601,
          outstanding_amount: invoice.outstanding_amount.to_s("F"),
          suggested_amount: suggested.to_s("F")
        }
      end

      suggestions
    end
  end
end
