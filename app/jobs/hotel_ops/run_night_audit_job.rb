# frozen_string_literal: true

# Temporary compatibility shim for jobs enqueued before the NightAudits extraction.
module HotelOps
  class RunNightAuditJob < NightAudits::RunJob
  end
end
