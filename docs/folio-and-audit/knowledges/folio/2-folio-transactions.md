# Folio: Transactions

## Status

Completed foundation with category and staff-workflow gaps.

## Purpose

Stores immutable folio ledger entries for guest charges, credits, payments, refunds, adjustments, taxes, and operational corrections.

## Key Files

- `app/models/folio_transaction.rb`
- `app/services/folios/insert_transaction.rb`
- `app/services/folios/post_staff_transaction.rb`
- `app/controllers/hotel_portal/folio_transactions_controller.rb`
- `spec/models/folio_transaction_spec.rb`
- `spec/services/folios/insert_transaction_spec.rb`

## Rules Made So Far

- Folio transactions are append-only for business purposes.
- Posted amounts are signed according to transaction type and category rules.
- Insertions pass through posting guard checks and record financial audit events.
- Staff posting exists for operational folio actions.

## Known Follow-Ups

- Expand staff posting categories if operations require manual Room, Tax, F&B, and Other postings.
- Add granular permissions for write-offs, refunds, corrections, and closed-date overrides.
- Ensure every valid transaction category has a default and hotel-specific GL mapping path.
