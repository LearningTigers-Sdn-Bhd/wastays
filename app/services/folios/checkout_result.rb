# frozen_string_literal: true

module Folios
  # Checkout closes every folio on a booking at once, so it answers with the
  # primary folio and the total balance across all of them.
  CheckoutResult = ApplicationResult.define(:folio, :balance)
end
