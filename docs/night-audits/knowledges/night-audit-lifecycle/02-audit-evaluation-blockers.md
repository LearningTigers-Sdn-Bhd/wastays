# Night Audit: Evaluation And Blockers

## Status

Mostly completed foundation with remaining guided-resolution polish.

## Purpose

Evaluates whether a business date can close and returns actionable blockers that staff must resolve first.

## Key Files

- `app/services/hotel_ops/evaluate_night_audit.rb`
- `app/controllers/hotel_portal/night_audits_controller.rb`
- `app/views/hotel_portal/night_audits/`
- `spec/requests/hotel_portal/night_audits_spec.rb`
- `spec/system/hotel/night_audits_spec.rb`

## Rules Made So Far

- Evaluation can detect operational and financial blockers before day close.
- Blocked audits do not advance the business date.
- Staff can review blockers through the hotel portal night audit flow.
- The night audit controller exposes a `blockers` endpoint for current blocker and exception details.
- Completed refund requests that have not been posted to the folio are detected as `refund_not_synced` blockers.

## Known Follow-Ups

- Deepen guided resolution actions for blocker categories that still require staff interpretation.
- Expand blocker coverage for POS closure and sync, pending check-ins, pending check-outs, package posting, and stale subsystem integrations.
- Add alerting for dates that remain blocked too long.
