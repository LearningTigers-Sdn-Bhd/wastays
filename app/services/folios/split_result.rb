# frozen_string_literal: true

module Folios
  # A split leaves the remainder on the source folio and puts the split-off
  # portion on the target, so both sides are reported. `transaction` is the
  # target side, which is what callers redirect to.
  SplitResult = ApplicationResult.define(:transaction, :source_transactions, :target_transactions, :operation_key)
end
