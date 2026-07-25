# frozen_string_literal: true

module Folios
  # Recovering a missing folio is idempotent, so success alone does not say
  # whether anything was built. `created?` does, and `message` phrases it for the
  # Night Audit blocker screen.
  RecoveryResult = ApplicationResult.define(:folio, :"created?", :message)
end
