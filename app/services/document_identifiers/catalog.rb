# frozen_string_literal: true

module DocumentIdentifiers
  module Catalog
    TYPES = {
      reservation: { counter: "reservation", code: "1" },
      guest_registration: { counter: "guest_registration", code: "2" },
      folio: { counter: "folio", code: "3" },
      ar_invoice: { counter: "ar_invoice", code: "4" },
      receipt: { counter: "receipt", code: "5" },
      tourism_tax_voucher: { counter: "tourism_tax_voucher", code: "6" },
      invoice: { counter: "invoice", code: "7" }
    }.freeze

    module_function

    def fetch(type)
      TYPES.fetch(type.to_sym)
    end
  end
end
