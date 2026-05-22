# Night Audit: Business Date Governance

## Status

Completed foundation.

## Purpose

Uses hotel business dates as the financial clock, decoupled from server time, so postings are controlled by audit state.

## Key Files

- `app/models/hotel_business_date.rb`
- `app/models/night_audit.rb`
- `app/services/hotel_ops/run_night_audit.rb`
- `app/services/financial_controls/posting_guard.rb`
- `spec/services/hotel_ops/run_night_audit_spec.rb`

## Rules Made So Far

- Business dates move through states such as `open`, `audit_running`, `audit_blocked`, `closed`, and `force_closed`.
- Closed, force-closed, or running audit dates are protected from normal posting.
- Night audit closes the audited date and opens or reuses the next open business date atomically.
- "Force Roll" allows an authorized manager to move a date from `audit_running` or `audit_blocked` to `force_closed` to ensure operational continuity.
- Manual "Force Roll" transitions are explicitly recorded as `business_date_force_closed` financial audit events for full traceability.
- Locked or unsafe next-date states cause safe audit failure instead of state overwrite.

## Known Follow-Ups

- Continue to test concurrency and duplicate-row race paths when day-roll logic changes.
- Surface date-lock state clearly in operational dashboards.
