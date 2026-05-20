# Financial Contracts: Financial Audit Events

## Status

Completed foundation.

## Purpose

Maintains an immutable audit trail for money-impacting actions and business-date state changes.

## Key Files

- `app/models/financial_audit_event.rb`
- `app/services/financial_controls/audit_event_recorder.rb`
- `app/services/folios/insert_transaction.rb`
- `app/services/folios/close_for_checkout.rb`
- `app/services/hotel_ops/run_night_audit.rb`

## Rules Made So Far

- Folio postings record audit events.
- Checkout closure records audit evidence.
- Night audit records completed, business-date closed, and business-date opened events.
- Request IDs and actor context are preserved where available for traceability.

## Known Follow-Ups

- Add finance-facing observability for abnormal event patterns.
- Add alerting for unbalanced folios, audit sync lag, and override abuse.
