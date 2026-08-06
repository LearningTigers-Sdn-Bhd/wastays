# frozen_string_literal: true

# Temporary compatibility shim for jobs enqueued before the NightAudits extraction.
class RunScheduledNightAuditsJob < NightAudits::RunScheduledJob
end
