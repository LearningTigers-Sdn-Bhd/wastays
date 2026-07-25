# frozen_string_literal: true

module Folios
  # Moving a charge moves its tax lines with it, so the move answers with every
  # transaction it touched and the operation key that ties them together in the
  # folio operation log.
  MoveResult = ApplicationResult.define(:transaction, :transactions, :operation_key)
end
