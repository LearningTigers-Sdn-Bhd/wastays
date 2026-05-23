# Booking Lifecycle: No-Show Processing

## Status

Completed for core folio/accounting classification.

## Purpose

Processes reservations that did not arrive by night audit, applies charges, and releases operational availability.

## Key Files

- `app/services/bookings/process_no_shows.rb`
- `app/services/hotel_ops/run_night_audit.rb`
- `app/services/folios/insert_transaction.rb`
- `app/models/folio_transaction.rb`
- `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb`

## Rules Made So Far

- Night audit can identify and process no-show bookings.
- No-show processing creates folio postings for charge-related room and tax amounts.
- No-show room charges post as `no_show_charge`; no-show tax posts as `tax`.
- `posting_source: no_show` is operational metadata and not the accounting classifier.
- No-show postings are protected by the same folio insertion and audit controls as other money-impacting activity.
- GL mapping and reports use the folio transaction category as the source of truth for no-show charges.

## Known Follow-Ups

- Add card-on-file or gateway authorization support before automated no-show charging is considered enterprise-ready.
