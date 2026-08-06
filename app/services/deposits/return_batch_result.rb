# frozen_string_literal: true

module Deposits
  ReturnBatchResult = ApplicationResult.define(:deposit_ids, :total, :method, :reference, :released_at)
end
