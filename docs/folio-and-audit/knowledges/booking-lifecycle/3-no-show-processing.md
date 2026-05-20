# Booking Lifecycle: No-Show Processing

## Status

Partially completed.

## Purpose

Processes reservations that did not arrive by night audit, applies penalties, and releases operational availability.

## Key Files

- `app/services/bookings/process_no_shows.rb`
- `app/services/hotel_ops/run_night_audit.rb`
- `app/services/folios/insert_transaction.rb`
- `app/models/folio_transaction.rb`
- `spec/integration/lifecycles/exception_booking_lifecycle_spec.rb`

## Rules Made So Far

- Night audit can identify and process no-show bookings.
- No-show processing can create folio postings for penalty-related room and tax amounts.
- No-show postings are protected by the same folio insertion and audit controls as other money-impacting activity.

## Known Follow-Ups

- Align no-show postings with the `no_show_penalty` category or document why metadata-based classification is preferred.
- Ensure GL mapping and reports treat no-show penalties consistently.
- Add card-on-file or gateway authorization support before automated no-show charging is considered enterprise-ready.
