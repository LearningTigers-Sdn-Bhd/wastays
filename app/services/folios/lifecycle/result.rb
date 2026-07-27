# frozen_string_literal: true

module Folios
  module Lifecycle
    # What a folio lifecycle operation answers: create, close, reopen, rename,
    # update. A failure still carries the folio it was asked about, so callers can
    # redirect back to it.
    Result = ApplicationResult.define(:folio)
  end
end
