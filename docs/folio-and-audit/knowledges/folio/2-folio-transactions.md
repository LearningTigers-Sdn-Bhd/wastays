# Folio: Transactions

## Status

Completed foundation with remaining category expansion and reporting gaps.

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
- Staff posting is split by granular permissions:
  - `post_folio_charges` for manual charge postings.
  - `post_folio_payments` for manual cash payment postings.
  - `execute_folio_refunds` for manual refund postings.
  - `post_folio_adjustments` for standard adjustments, discounts, and other adjustments.
  - `post_folio_corrections` for correction postings and reversals.
  - `post_folio_write_offs` for write-off postings.
- The legacy `post_folio_transactions` permission is no longer used for authorization.
- Valid folio categories are covered by default GL mappings, including `no_show_charge`, `late_checkout_charge`, and `early_departure_charge`.

## Known Follow-Ups

- Expand staff posting categories if operations require manual Room, Tax, F&B, and Other postings.
- Keep hotel-specific GL mapping behavior aligned across journal batches and folio ledger exports.
