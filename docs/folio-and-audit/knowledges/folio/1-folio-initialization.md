# Folio: Initialization

## Status

Completed foundation.

## Purpose

Creates the guest financial ledger for a booking and applies existing captured payments as opening credits.

## Key Files

- `app/models/booking_folio.rb`
- `app/services/folios/initialize_for_booking.rb`
- `app/services/folios/sync_existing_payments.rb`
- `app/services/folios/record_payment_from_gateway.rb`
- `spec/integration/lifecycles/standard_booking_lifecycle_spec.rb`

## Rules Made So Far

- Each booking can receive a folio for stay-related financial activity.
- Captured booking payments are synchronized into the folio as `advance_deposit` transactions.
- Initialization is idempotent enough to avoid duplicate folio setup during normal check-in flows.

## Known Follow-Ups

- Add Deposit Liability reporting for unearned advance deposits.
- Keep gateway reference IDs visible in downstream refund and reconciliation workflows.
