# frozen_string_literal: true

module FolioRouting
  # What applying a batch of billing-route changes answers: every transaction the
  # change relocated. An idempotent replay reports no transactions rather than
  # failing, because the batch already completed.
  BatchResult = ApplicationResult.define(:transactions)
end
