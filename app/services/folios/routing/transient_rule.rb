# frozen_string_literal: true

module Folios
  module Routing
    # A tax code inherits its parent's destination even when no rule of its own was
    # saved. ApplyExistingCharges wants a rule to move charges by, so it is handed
    # this unsaved stand-in instead.
    #
    # The members are exactly what ApplyExistingCharges and PreviewExistingCharges
    # read off a rule. Declaring them means a reader reaching for anything else
    # fails here, rather than silently getting nil and moving no charges.
    TransientRule = Data.define(
      :booking, :booking_id, :transaction_code_id,
      :target_folio, :target_folio_id, :effective_from, :effective_until
    )
  end
end
