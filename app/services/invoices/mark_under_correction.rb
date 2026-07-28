# frozen_string_literal: true

module Invoices
  class MarkUnderCorrection
    def self.call!(folio:)
      invoice = folio.invoice
      return if invoice.blank?

      raise ArgumentError, "Voided folio invoices cannot be reopened for correction." if invoice.voided?

      invoice.update!(state: "under_correction") unless invoice.under_correction?
      invoice
    end
  end
end
