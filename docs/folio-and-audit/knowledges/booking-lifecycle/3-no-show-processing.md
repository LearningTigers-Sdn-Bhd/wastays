# Booking Lifecycle: No-Show Processing

## Status

Completed for core folio/accounting classification.

## Purpose

Places missed arrivals into a temporary review state, then finalizes unresolved no-shows after staff action or the next business-date night audit attempt.

## Key Files

- `app/services/bookings/review_missed_arrivals.rb`
- `app/services/bookings/process_no_show_reviews.rb`
- `app/services/bookings/finalize_no_show.rb`
- `app/services/hotel_ops/run_night_audit.rb`
- `app/services/folios/insert_transaction.rb`
- `app/models/folio_transaction.rb`
- `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb`

## Rules Made So Far

- The first night audit moves eligible missed arrivals from `confirmed` to `review_no_show` without posting charges or releasing availability.
- Staff can backdate check-in, cancel, or finalize a booking while it is in `review_no_show`.
- A later business-date night audit attempt automatically finalizes unresolved reviews.
- No-show processing creates folio postings for charge-related room and tax amounts.
- Finalization posts charges to the original review business date using an audited closed-date override when required.
- No-show room charges post as `no_show_charge`; no-show tax posts as `tax`.
- `posting_source: no_show` is operational metadata and not the accounting classifier.
- No-show postings are protected by the same folio insertion and audit controls as other money-impacting activity.
- General Ledger (GL) mapping and reports use the folio transaction category as the source of truth for no-show charges.

## Known Follow-Ups

- Add card-on-file or gateway authorization support before automated no-show charging is considered enterprise-ready.
