# Night Audit: Run Night Audit

## Status

Completed foundation.

## Purpose

Coordinates the nightly close process: evaluate blockers, post earned charges, process no-shows, create summaries, close the date, and open the next date.

## Key Files

- `app/services/hotel_ops/run_night_audit.rb`
- `app/jobs/hotel_ops/run_night_audit_job.rb`
- `app/jobs/run_scheduled_night_audits_job.rb`
- `app/models/night_audit.rb`
- `app/models/night_audit_financial_summary.rb`
- `spec/services/hotel_ops/run_night_audit_spec.rb`

## Rules Made So Far

- Audit runs use row locks to prevent duplicate close attempts.
- Successful audits post nightly room and tax charges.
- Successful audits process no-show reservations.
- Successful audits persist financial summaries and audit events.
- Failed or blocked audits do not open the next business date unless a "Force Roll" is initiated.
- "Force Roll" bypasses blockers to advance the business date and is recorded as `night_audit_force_rolled`.

## Known Follow-Ups

- Add package posting if packages become part of rate plans.
- Add operational alerts for failed scheduled audits.
- Ensure scheduled jobs are monitored in production.
