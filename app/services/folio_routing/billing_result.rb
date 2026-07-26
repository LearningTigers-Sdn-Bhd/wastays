# frozen_string_literal: true

module FolioRouting
  # What billing a booking's room charges to a company answers: the billing
  # party it ensured, and the folio now receiving the charges.
  BillingResult = ApplicationResult.define(:party, :target_folio)
end
